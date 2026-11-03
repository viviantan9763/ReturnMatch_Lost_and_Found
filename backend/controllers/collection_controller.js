// ReturnMatch: OTP-first collection counter (ADMIN / SUPER_ADMIN only).
// Uses existing claim_otp plaintext schema for compatibility. Do not log OTPs.
const pool = require('../config/db');
const lifecycle = require('../services/item_lifecycle_service');
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
    await lifecycle.withCollectibleClaim(r.claim_id, async () => {});
    return res.json({ collection: {
      claim_id: r.claim_id, item_id: r.item_id,
      item_name: r.item_name, value_tier: r.value_tier,
      location: r.location, custody_status: r.custody_status,
      claimant_name: r.claimant_name, claimant_email: r.claimant_email,
      claim_status: r.claim_status, expires_at: r.expired_at
    }});
  } catch (e) {
    return lifecycle.respondError(res, e, 'Unable to look up collection');
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
  try {
    const claim = await lifecycle.collect(claimId, otp, req.user.user_id);
    return res.json({ message: 'Collection completed successfully', claim });
  } catch (error) {
    return lifecycle.respondError(res, error, 'Unable to confirm collection. Refresh before retrying.');
  }
};

module.exports = { lookupCollection, confirmCollection };
