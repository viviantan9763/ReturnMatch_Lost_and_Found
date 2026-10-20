const pool = require('../config/db');
const crypto = require('crypto');
const admin = u => u && ['ADMIN','SUPER_ADMIN'].includes(u.role);
const norm = s => String(s ?? '').trim().toLowerCase();
const hash = s => crypto.createHash('sha256').update(norm(s)).digest('hex');
const validId = x => Number.isSafeInteger(Number(x)) && Number(x) > 0;

// Public to the claimant: only question numbers/text, never trusted answers/hashes.
const getSecurityQuestions = async (req,res) => {
  if (!validId(req.params.claimId)) return res.status(400).json({message:'Invalid claim ID'});
  try {
    const [rows] = await pool.query(`SELECT c.claimant_id,c.claim_status,c.item_id,i.value_tier
      FROM claim c JOIN item i ON i.item_id=c.item_id WHERE c.claim_id=?`,[req.params.claimId]);
    if (!rows.length) return res.status(404).json({message:'Claim not found'});
    if (Number(rows[0].claimant_id)!==Number(req.user.user_id) && !admin(req.user)) return res.status(403).json({message:'Access denied'});
    const [questions] = await pool.query(`SELECT question_no,question_text FROM item_security_question
      WHERE item_id=? ORDER BY question_no`,[rows[0].item_id]);
    return res.json({claim_id:Number(req.params.claimId),claim_status:rows[0].claim_status,
      value_tier:rows[0].value_tier,questions});
  } catch(e) {console.error('Get questions:',e);return res.status(500).json({message:'Failed to load security questions'});}
};

// answers: [{question_no:1,answer_text:'...'}, {question_no:2,answer_text:'...'}]
const submitSecurityAnswers = async (req,res) => {
  if (!validId(req.params.claimId)) return res.status(400).json({message:'Invalid claim ID'});
  const answers=req.body?.answers;
  if (!Array.isArray(answers)||answers.length!==2 ||
      new Set(answers.map(a=>Number(a?.question_no))).size!==2 ||
      answers.some(a=>![1,2].includes(Number(a?.question_no)) || typeof a?.answer_text!=='string' ||
        norm(a.answer_text).length<2 || norm(a.answer_text).length>250))
    return res.status(400).json({message:'Exactly two numbered answers (1 and 2) are required'});
  const connection=await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [claims]=await connection.query(`SELECT c.claim_id,c.claimant_id,c.claim_status,c.item_id,
      i.value_tier,i.status AS item_status,i.item_type,i.publication_status
      FROM claim c JOIN item i ON c.item_id=i.item_id WHERE c.claim_id=? FOR UPDATE`,[req.params.claimId]);
    if (!claims.length) {await connection.rollback();return res.status(404).json({message:'Claim not found'});}
    const claim=claims[0];
    if (Number(claim.claimant_id)!==Number(req.user.user_id)) {await connection.rollback();return res.status(403).json({message:'Not your claim'});}
    if (claim.claim_status!=='PENDING') {await connection.rollback();return res.status(409).json({message:'Answers already submitted or claim is no longer pending'});}
    if (claim.item_type!=='FOUND'||claim.publication_status!=='PUBLISHED'||
        !['ACTIVE','MATCHED','CLAIM_PENDING'].includes(claim.item_status)) {
      await connection.rollback();return res.status(409).json({message:'Item is unavailable'});
    }
    const [qs]=await connection.query(`SELECT question_no,question_text,answer_hash
      FROM item_security_question WHERE item_id=? ORDER BY question_no`,[claim.item_id]);
    if (qs.length!==2) {await connection.rollback();return res.status(409).json({message:'Item has no complete security questions. Contact admin.'});}
    const [existing]=await connection.query('SELECT answer_id FROM security_answer WHERE claim_id=? LIMIT 1',[claim.claim_id]);
    if (existing.length) {await connection.rollback();return res.status(409).json({message:'Answers already submitted'});}
    let allCorrect=true;
    for (const q of qs) {
      const provided=answers.find(a=>Number(a.question_no)===Number(q.question_no));
      if (!provided) {await connection.rollback();return res.status(400).json({message:'Missing answer'});}
      const correct=crypto.timingSafeEqual(Buffer.from(hash(provided.answer_text),'hex'),Buffer.from(q.answer_hash,'hex'));
      allCorrect=allCorrect&&correct;
      await connection.query(`INSERT INTO security_answer (claim_id,question_no,question_text,answer_text,is_correct)
        VALUES (?,?,?,?,?)`,[claim.claim_id,q.question_no,q.question_text,provided.answer_text,correct?1:0]);
    }
    // Only MEDIUM with both correct answers can auto-approve. HIGH always admin-reviewed.
    let status='VERIFICATION_REQUIRED';
    if (claim.value_tier==='MEDIUM'&&allCorrect) {
      // Lock the item to avoid multiple simultaneous approvals.
      const [items]=await connection.query('SELECT item_id,status FROM item WHERE item_id=? FOR UPDATE',[claim.item_id]);
      const [approved]=await connection.query(`SELECT claim_id FROM claim WHERE item_id=?
        AND claim_status IN ('APPROVED','COLLECTED') LIMIT 1 FOR UPDATE`,[claim.item_id]);
      if (approved.length || !['ACTIVE','MATCHED','CLAIM_PENDING'].includes(items[0]?.status)) {
        await connection.rollback();return res.status(409).json({message:'Item has an existing approved claim'});
      }
      status='APPROVED';
      await connection.query(`UPDATE claim SET claim_status='APPROVED',reviewed_at=NOW(),approved_at=NOW()
        WHERE claim_id=?`,[claim.claim_id]);
      // Item remains visible for staff, but other claims must not be approved.
    } else {
      await connection.query(`UPDATE claim SET claim_status='VERIFICATION_REQUIRED' WHERE claim_id=?`,[claim.claim_id]);
    }
    await connection.commit();
    return res.status(201).json({message:status==='APPROVED'?'Claim automatically approved':'Answers submitted for manual review',
      claim:{claim_id:Number(claim.claim_id),claim_status:status,value_tier:claim.value_tier,answers_submitted:2}});
  } catch(e) {try{await connection.rollback();}catch(_){} console.error('Submit answers:',e);
    return res.status(500).json({message:'Failed to submit answers'});
  } finally {connection.release();}
};

const getSecurityAnswers=async(req,res)=>{
  if (!validId(req.params.claimId)) return res.status(400).json({message:'Invalid claim ID'});
  try {
    const [claims]=await pool.query(`SELECT c.claimant_id,c.claim_status,i.item_name,i.value_tier
      FROM claim c JOIN item i ON i.item_id=c.item_id WHERE c.claim_id=?`,[req.params.claimId]);
    if (!claims.length)return res.status(404).json({message:'Claim not found'});
    const own=Number(claims[0].claimant_id)===Number(req.user.user_id);
    if (!own&&!admin(req.user))return res.status(403).json({message:'Access denied'});
    const [rows]=await pool.query(`SELECT answer_id,question_no,question_text,answer_text,is_correct,answered_at
      FROM security_answer WHERE claim_id=? ORDER BY question_no`,[req.params.claimId]);
    // Only admin may see verification verdict; no one sees trusted reference answers.
    const answers=admin(req.user)?rows:rows.map(({is_correct,...safe})=>safe);
    return res.json({claim:{claim_id:Number(req.params.claimId),item_name:claims[0].item_name,
      value_tier:claims[0].value_tier,claim_status:claims[0].claim_status},answers});
  }catch(e){console.error('Get answers:',e);return res.status(500).json({message:'Failed to load answers'});}
};
module.exports={getSecurityQuestions,submitSecurityAnswers,getSecurityAnswers};
