const pool=require('../config/db');
const crypto=require('crypto');
const {createAuditLog}=require('../services/audit_log_service');
const isAdmin=u=>u&&['ADMIN','SUPER_ADMIN'].includes(u.role);
const idOK=x=>Number.isSafeInteger(Number(x))&&Number(x)>0;
const codeOK=x=>typeof x==='string'&&/^\d{6}$/.test(x);
// On-demand OTP generation by staff when claimant arrives. 10-minute window.
const generateOtp=async(req,res)=>{
  if(!isAdmin(req.user))return res.status(403).json({message:'Admin access required'});
  if(!idOK(req.params.claimId))return res.status(400).json({message:'Invalid claim ID'});
  const connection=await pool.getConnection();
  try{
    await connection.beginTransaction();
    const [claims]=await connection.query(`SELECT c.claim_id,c.claim_status,c.item_id,i.status AS item_status
      FROM claim c JOIN item i ON i.item_id=c.item_id WHERE c.claim_id=? FOR UPDATE`,[req.params.claimId]);
    if(!claims.length){await connection.rollback();return res.status(404).json({message:'Claim not found'});}
    if(claims[0].claim_status!=='APPROVED'||!['ACTIVE','MATCHED','CLAIM_PENDING'].includes(claims[0].item_status)){
      await connection.rollback();return res.status(409).json({message:'Claim is not ready for collection'});
    }
    await connection.query(`UPDATE claim_otp SET otp_status='EXPIRED',expired_at=NOW()
      WHERE claim_id=? AND otp_status='ACTIVE'`,[req.params.claimId]);
    // Avoid collisions with any other currently valid OTP for OTP-first admin lookup.
    let code;
    for(let n=0;n<20;n++){
      const candidate=String(crypto.randomInt(100000,1000000));
      const [collision]=await connection.query(`SELECT otp_id FROM claim_otp WHERE otp_code=?
        AND otp_status='ACTIVE' AND expired_at>NOW() LIMIT 1`,[candidate]);
      if(!collision.length){code=candidate;break;}
    }
    if(!code)throw new Error('Unable to allocate unique OTP');
    const [result]=await connection.query(`INSERT INTO claim_otp
      (claim_id,otp_code,otp_status,generated_at,expired_at)
      VALUES (?,?,'ACTIVE',NOW(),DATE_ADD(NOW(),INTERVAL 10 MINUTE))`,[req.params.claimId,code]);
    await connection.commit();
    return res.status(201).json({message:'Collection OTP generated. Valid for 10 minutes.',
      otp:{otp_id:result.insertId,claim_id:Number(req.params.claimId),otp_code:code,expires_in_minutes:10}});
  }catch(e){try{await connection.rollback();}catch(_){}console.error('Generate OTP:',e);
    return res.status(500).json({message:'Failed to generate OTP'});
  }finally{connection.release();}
};
const getActiveOtp=async(req,res)=>{
  if(!idOK(req.params.claimId))return res.status(400).json({message:'Invalid claim ID'});
  try{
    const [claims]=await pool.query('SELECT claimant_id,claim_status FROM claim WHERE claim_id=?',[req.params.claimId]);
    if(!claims.length)return res.status(404).json({message:'Claim not found'});
    if(Number(claims[0].claimant_id)!==Number(req.user.user_id)&&!isAdmin(req.user))return res.status(403).json({message:'Access denied'});
    if(claims[0].claim_status!=='APPROVED')return res.status(409).json({message:'Claim is not approved'});
    const [otps]=await pool.query(`SELECT otp_id,claim_id,otp_code,otp_status,generated_at,expired_at
      FROM claim_otp WHERE claim_id=? AND otp_status='ACTIVE' AND expired_at>NOW()
      ORDER BY generated_at DESC LIMIT 1`,[req.params.claimId]);
    if(!otps.length)return res.status(404).json({message:'No valid OTP. Ask staff to generate one at collection.'});
    return res.json({otp:otps[0]});
  }catch(e){console.error('Get OTP:',e);return res.status(500).json({message:'Failed to load OTP'});}
};
// Legacy claim-specific endpoint. Admin collection screen also supports OTP-first lookup.
const verifyOtp=async(req,res)=>{
  if(!isAdmin(req.user))return res.status(403).json({message:'Admin access required'});
  if(!idOK(req.params.claimId)||!codeOK(req.body?.otp_code))return res.status(400).json({message:'Valid claim ID and 6-digit OTP required'});
  const connection=await pool.getConnection();
  try{
    await connection.beginTransaction();
    const [claims]=await connection.query(`SELECT c.item_id,c.claim_status,i.status AS item_status
      FROM claim c JOIN item i ON i.item_id=c.item_id WHERE c.claim_id=? FOR UPDATE`,[req.params.claimId]);
    if(!claims.length){await connection.rollback();return res.status(404).json({message:'Claim not found'});}
    if(claims[0].claim_status!=='APPROVED'||!['ACTIVE','MATCHED','CLAIM_PENDING'].includes(claims[0].item_status)){
      await connection.rollback();return res.status(409).json({message:'Claim or item unavailable'});
    }
    const [otps]=await connection.query(`SELECT otp_id FROM claim_otp WHERE claim_id=? AND otp_code=?
      AND otp_status='ACTIVE' AND expired_at>NOW() FOR UPDATE`,[req.params.claimId,req.body.otp_code]);
    if(otps.length!==1){await connection.rollback();return res.status(400).json({message:'Invalid or expired OTP'});}
    await connection.query(`UPDATE claim_otp SET otp_status='USED',used_at=NOW() WHERE otp_id=?`,[otps[0].otp_id]);
    await connection.query(`UPDATE claim SET claim_status='COLLECTED' WHERE claim_id=?`,[req.params.claimId]);
    await connection.query(`UPDATE item SET status='CLAIMED' WHERE item_id=?`,[claims[0].item_id]);
    await createAuditLog({admin_id:req.user.user_id,item_id:claims[0].item_id,claim_id:Number(req.params.claimId),
      action_type:'CLAIM_COLLECTED',action_details:`Claim ${req.params.claimId} collected using OTP.`,connection});
    await connection.commit();
    return res.json({message:'Collection completed',claim:{claim_id:Number(req.params.claimId),claim_status:'COLLECTED'}});
  }catch(e){try{await connection.rollback();}catch(_){}console.error('Verify OTP:',e);
    return res.status(500).json({message:'Failed to verify OTP. Check audit log enum compatibility.'});
  }finally{connection.release();}
};
module.exports={generateOtp,getActiveOtp,verifyOtp};
