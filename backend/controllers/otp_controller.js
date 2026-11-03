const pool = require('../config/db');
const crypto = require('crypto');
const lifecycle = require('../services/item_lifecycle_service');
const isAdmin = u => u && ['ADMIN', 'SUPER_ADMIN'].includes(u.role);
const idOK = x => Number.isSafeInteger(Number(x)) && Number(x) > 0;
const codeOK = x => typeof x === 'string' && /^\d{6}$/.test(x);

// On-demand generation requires verified office custody, just like handover.
const generateOtp = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  if (!idOK(req.params.claimId)) return res.status(400).json({ message: 'Invalid claim ID' });
  try {
    const otp = await lifecycle.withCollectibleClaim(Number(req.params.claimId), async (connection, item, claim) => {
      await connection.query(`UPDATE claim_otp SET otp_status='EXPIRED', expired_at=NOW()
        WHERE claim_id=? AND otp_status='ACTIVE'`, [claim.claim_id]);
      let code;
      for (let n = 0; n < 20; n++) {
        const candidate = String(crypto.randomInt(100000, 1000000));
        const [collision] = await connection.query(`SELECT otp_id FROM claim_otp WHERE otp_code=?
          AND otp_status='ACTIVE' AND expired_at>NOW() LIMIT 1`, [candidate]);
        if (!collision.length) { code = candidate; break; }
      }
      if (!code) throw new Error('Unable to allocate unique OTP');
      const [result] = await connection.query(`INSERT INTO claim_otp
        (claim_id,otp_code,otp_status,generated_at,expired_at)
        VALUES (?,?,'ACTIVE',NOW(),DATE_ADD(NOW(),INTERVAL 10 MINUTE))`, [claim.claim_id, code]);
      return { otp_id: result.insertId, claim_id: claim.claim_id, otp_code: code, expires_in_minutes: 10 };
    });
    return res.status(201).json({ message: 'Collection OTP generated. Valid for 10 minutes.', otp });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to generate OTP'); }
};
const getActiveOtp = async (req, res) => {
  if (!idOK(req.params.claimId)) return res.status(400).json({ message: 'Invalid claim ID' });
  try {
    const [claims] = await pool.query('SELECT claimant_id,claim_status FROM claim WHERE claim_id=?', [req.params.claimId]);
    if (!claims.length) return res.status(404).json({ message: 'Claim not found' });
    if (Number(claims[0].claimant_id) !== Number(req.user.user_id) && !isAdmin(req.user)) {
      return res.status(403).json({ message: 'Access denied' });
    }
    const otp = await lifecycle.withCollectibleClaim(Number(req.params.claimId), async (connection) => {
      const [otps] = await connection.query(`SELECT otp_id,claim_id,otp_code,otp_status,generated_at,expired_at
        FROM claim_otp WHERE claim_id=? AND otp_status='ACTIVE' AND expired_at>NOW()
        ORDER BY generated_at DESC LIMIT 1`, [req.params.claimId]);
      if (!otps.length) lifecycle.fail('No valid OTP. Ask staff to generate one at collection.', 404);
      return otps[0];
    });
    return res.json({ otp });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to load OTP'); }
};
// Both public collection routes delegate to exactly the same atomic transition.
const verifyOtp = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  if (!idOK(req.params.claimId) || !codeOK(req.body?.otp_code)) {
    return res.status(400).json({ message: 'Valid claim ID and 6-digit OTP required' });
  }
  try {
    const claim = await lifecycle.collect(Number(req.params.claimId), req.body.otp_code, req.user.user_id);
    return res.json({ message: 'Collection completed', claim });
  } catch (error) { return lifecycle.respondError(res, error, 'Unable to confirm collection. Refresh before retrying.'); }
};
module.exports = { generateOtp, getActiveOtp, verifyOtp };
