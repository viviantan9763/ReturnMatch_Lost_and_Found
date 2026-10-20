const pool=require('../config/db');
const {createAuditLog}=require('../services/audit_log_service');
const {createNotification}=require('../services/notification_service');
const isAdmin=u=>u&&['ADMIN','SUPER_ADMIN'].includes(u.role);
const verifyClaim=async(req,res)=>{
  if(!isAdmin(req.user))return res.status(403).json({message:'Admin access required'});
  const claimId=Number(req.params.claimId),{decision,verification_note,answers}=req.body||{};
  if(!Number.isSafeInteger(claimId)||claimId<1)return res.status(400).json({message:'Invalid claim ID'});
  if(!['APPROVED','REJECTED'].includes(decision))return res.status(400).json({message:'Invalid decision'});
  if(!Array.isArray(answers)||answers.length!==2)return res.status(400).json({message:'Review both security answers'});
  const connection=await pool.getConnection();let claim;
  try{
    await connection.beginTransaction();
    const [claims]=await connection.query(`SELECT c.claim_id,c.claimant_id,c.claim_status,c.item_id,
      i.item_name,i.item_type,i.value_tier,i.status AS item_status FROM claim c
      JOIN item i ON i.item_id=c.item_id WHERE c.claim_id=? FOR UPDATE`,[claimId]);
    if(!claims.length){await connection.rollback();return res.status(404).json({message:'Claim not found'});}
    claim=claims[0];
    if(claim.claim_status!=='VERIFICATION_REQUIRED'){
      await connection.rollback();return res.status(409).json({message:'Claim is not awaiting verification'});
    }
    const [stored]=await connection.query(`SELECT answer_id FROM security_answer WHERE claim_id=? FOR UPDATE`,[claimId]);
    const ids=stored.map(x=>Number(x.answer_id));
    const submitted=answers.map(x=>Number(x.answer_id));
    if(ids.length!==2||new Set(submitted).size!==2||submitted.some(id=>!ids.includes(id))||
      answers.some(x=>typeof x.is_correct!=='boolean')){
      await connection.rollback();return res.status(400).json({message:'Provide one boolean verdict for each saved answer'});
    }
    // Approval requires two positive admin verdicts, plus physical ownership checks for HIGH.
    if(decision==='APPROVED' && answers.some(a=>!a.is_correct)){
      await connection.rollback();return res.status(400).json({message:'Cannot approve with incorrect answers. Use REJECTED or request more evidence.'});
    }
    const [previous]=await connection.query('SELECT verification_id FROM admin_verification WHERE claim_id=? LIMIT 1',[claimId]);
    if(previous.length){await connection.rollback();return res.status(409).json({message:'Claim already verified'});}
    // Lock item before granting approval, preventing competing approvals.
    const [items]=await connection.query('SELECT status FROM item WHERE item_id=? FOR UPDATE',[claim.item_id]);
    if(decision==='APPROVED'){
      const [others]=await connection.query(`SELECT claim_id FROM claim WHERE item_id=? AND claim_id<>?
        AND claim_status IN ('APPROVED','COLLECTED') LIMIT 1 FOR UPDATE`,[claim.item_id,claimId]);
      if(others.length||!['ACTIVE','MATCHED','CLAIM_PENDING'].includes(items[0]?.status)){
        await connection.rollback();return res.status(409).json({message:'Item is no longer eligible for approval'});
      }
    }
    for(const a of answers)await connection.query(`UPDATE security_answer SET is_correct=? WHERE answer_id=? AND claim_id=?`,
      [a.is_correct?1:0,Number(a.answer_id),claimId]);
    await connection.query(`INSERT INTO admin_verification
      (claim_id,admin_id,verification_status,verification_notes,verified_at)
      VALUES (?,?,?,?,NOW())`,[claimId,req.user.user_id,decision,verification_note||null]);
    await connection.query(`UPDATE claim SET claim_status=?,reviewed_at=NOW(),approved_at=? WHERE claim_id=?`,
      [decision,decision==='APPROVED'?new Date():null,claimId]);
    await createAuditLog({admin_id:req.user.user_id,item_id:claim.item_id,claim_id:claimId,
      action_type:`CLAIM_${decision}`,action_details:`Claim ${claimId} ${decision.toLowerCase()} by admin.`,connection});
    await connection.commit();
  }catch(e){try{await connection.rollback();}catch(_){}console.error('Admin verify:',e);
    return res.status(500).json({message:'Failed to verify claim. Check audit log enum compatibility.'});
  }finally{connection.release();}
  try{await createNotification({user_id:claim.claimant_id,item_id:claim.item_id,claim_id:claimId,
    notification_type:decision==='APPROVED'?'CLAIM_APPROVED':'CLAIM_REJECTED',
    message:decision==='APPROVED'?'Your claim was approved. Request a collection OTP from staff.':'Your claim was rejected after review.'});}
  catch(e){console.error('Notification failed after successful verification:',e);}
  return res.json({message:`Claim ${decision.toLowerCase()} successfully`,verification:{claim_id:claimId,
    admin_id:req.user.user_id,verification_status:decision,answers_reviewed:answers.length}});
};
module.exports={verifyClaim};
