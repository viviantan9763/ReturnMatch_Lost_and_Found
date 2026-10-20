// ReturnMatch: OTP-first collection counter (ADMIN / SUPER_ADMIN only).
// Uses existing claim_otp plaintext schema for compatibility. Do not log OTPs.
const pool = require('../config/db');
const { createAuditLog } = require('../services/audit_log_service');
const isAdmin = (u) => u && ['ADMIN', 'SUPER_ADMIN'].includes(u.role);
const validOtp = (v) => typeof v === 'string' && /^\d{6}$/.test(v);

// Lightweight per-admin throttling; production deployments should use a shared
// store (e.g. Redis) and also enforce IP throttling at the reverse proxy.
const attempts = new Map();
function allowAttempt(userId) {
  const now = Date.now();
  const key = String(userId);
  const record = attempts.get(key);
  if (!record || now - record.start >= 15 * 60 * 1000) {
    attempts.set(key, { start: now, count: 1 });
    return true;
  }
  if (record.count >= 10) return false;
  record.count += 1;
  return true;
}

const claimLookupSql = `
  SELECT o.otp_id, o.claim_id, o.expired_at,
         c.claimant_id, c.item_id, c.claim_status,
         i.item_name, i.item_type, i.value_tier, i.status AS item_status,
         i.location, i.custody_status, u.name AS claimant_name,
         u.email AS claimant_email
  FROM claim_otp o
  JOIN claim c ON c.claim_id = o.claim_id
  JOIN item i ON i.item_id = c.item_id
  JOIN user u ON u.user_id = c.claimant_id
  WHERE o.otp_code = ? AND o.otp_status = 'ACTIVE'
    AND o.expired_at > NOW()
  ORDER BY o.generated_at DESC
`;

const lookupCollection = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  const otp = req.body?.otp_code;
  if (!validOtp(otp)) return res.status(400).json({ message: 'Enter a valid 6-digit OTP' });
  if (!allowAttempt(req.user.user_id)) return res.status(429).json({ message: 'Too many OTP lookups. Try again later.' });
  try {
    const [rows] = await pool.query(claimLookupSql, [otp]);
    if (rows.length === 0) return res.status(404).json({ message: 'OTP not found or expired' });
    if (rows.length > 1) return res.status(409).json({ message: 'OTP collision. Regenerate a code for this claim.' });
    const r = rows[0];
    if (r.claim_status !== 'APPROVED' || r.item_type !== 'FOUND' ||
        !['ACTIVE', 'MATCHED', 'CLAIM_PENDING'].includes(r.item_status)) {
      return res.status(409).json({ message: 'Claim or item is not eligible for collection' });
    }
    return res.json({ collection: {
      claim_id: r.claim_id, item_id: r.item_id,
      item_name: r.item_name, value_tier: r.value_tier,
      location: r.location, custody_status: r.custody_status,
      claimant_name: r.claimant_name, claimant_email: r.claimant_email,
      claim_status: r.claim_status, expires_at: r.expired_at
    }});
  } catch (e) {
    console.error('OTP collection lookup failed:', e);
    return res.status(500).json({ message: 'Unable to look up collection' });
  }
};

const confirmCollection = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  const otp = req.body?.otp_code;
  const claimId = Number(req.body?.claim_id);
  if (!validOtp(otp) || !Number.isSafeInteger(claimId) || claimId < 1) {
    return res.status(400).json({ message: 'Valid OTP and claim ID are required' });
  }
  if (!allowAttempt(req.user.user_id)) return res.status(429).json({ message: 'Too many attempts. Try again later.' });
  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [claims] = await connection.query(
      `SELECT c.claim_id, c.item_id, c.claim_status, i.item_type, i.status AS item_status
       FROM claim c JOIN item i ON i.item_id = c.item_id
       WHERE c.claim_id = ? FOR UPDATE`, [claimId]);
    if (!claims.length) {
      await connection.rollback();
      return res.status(404).json({ message: 'Claim not found' });
    }
    const claim = claims[0];
    if (claim.claim_status !== 'APPROVED' || claim.item_type !== 'FOUND' ||
        !['ACTIVE', 'MATCHED', 'CLAIM_PENDING'].includes(claim.item_status)) {
      await connection.rollback();
      return res.status(409).json({ message: 'Claim or item is no longer available' });
    }
    const [otps] = await connection.query(
      `SELECT otp_id FROM claim_otp WHERE claim_id = ? AND otp_code = ?
         AND otp_status = 'ACTIVE' AND expired_at > NOW() FOR UPDATE`,
      [claimId, otp]);
    if (otps.length !== 1) {
      await connection.rollback();
      return res.status(400).json({ message: 'Invalid, expired, or ambiguous OTP' });
    }
    await connection.query(
      `UPDATE claim_otp SET otp_status = 'USED', used_at = NOW() WHERE otp_id = ?`,
      [otps[0].otp_id]);
    await connection.query(`UPDATE claim SET claim_status = 'COLLECTED' WHERE claim_id = ?`, [claimId]);
    // Existing project uses item.status = CLAIMED after successful collection.
    await connection.query(`UPDATE item SET status = 'CLAIMED' WHERE item_id = ?`, [claim.item_id]);
    await createAuditLog({
      admin_id: req.user.user_id, item_id: claim.item_id, claim_id: claimId,
      action_type: 'CLAIM_COLLECTED',
      action_details: `Claim ${claimId} physically handed over after OTP verification.`,
      connection
    });
    await connection.commit();
    return res.json({ message: 'Collection completed successfully',
      claim: { claim_id: claimId, claim_status: 'COLLECTED', item_id: claim.item_id, item_status: 'CLAIMED' } });
  } catch (e) {
    try { await connection.rollback(); } catch (_) {}
    console.error('OTP collection confirmation failed:', e);
    return res.status(500).json({ message: 'Unable to confirm collection. Check audit_log action_type compatibility.' });
  } finally { connection.release(); }
};

module.exports = { lookupCollection, confirmCollection };
