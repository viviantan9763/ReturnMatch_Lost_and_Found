const pool = require('../config/db');

// ----------------------------------------------------
// CREATE CLAIM
// POST /api/claims
// USER claims a FOUND item
// ----------------------------------------------------

const {
  generateOtp,
  getActiveOtp,
  verifyOtp
} = require('../controllers/otp_controller');

const lifecycle = require('../services/item_lifecycle_service');
const createClaim = async (req, res) => {
  const claimantId = req.user.user_id;
  const { item_id, claim_reason } = req.body;
  if (!Number.isSafeInteger(Number(item_id)) || Number(item_id) < 1) {
    return res.status(400).json({ message: 'Valid item ID is required' });
  }
  try {
    const claim = await lifecycle.withItem(Number(item_id), async (connection, item) => {
      if (item.item_type !== 'FOUND') lifecycle.fail('Only found items can be claimed', 400);
      if (item.publication_status !== 'PUBLISHED') lifecycle.fail('Item is not published for claims');
      if (Number(item.reporter_id) === Number(claimantId)) lifecycle.fail('You cannot claim an item you reported', 403);
      if (!lifecycle.available(item)) lifecycle.fail('This item is no longer available for claim', 400);
      const [approved] = await connection.query(`SELECT claim_id FROM claim WHERE item_id=?
        AND claim_status IN ('APPROVED','COLLECTED') ORDER BY claim_id FOR UPDATE`, [item_id]);
      if (approved.length) lifecycle.fail('Item already has an approved claim');
      if (lifecycle.blockingDisposals(await lifecycle.disposals(connection, item_id)).length) {
        lifecycle.fail('Item is reserved for disposal or has already been disposed');
      }
      const [existing] = await connection.query(`SELECT claim_id FROM claim WHERE item_id = ? AND claimant_id = ?
        AND claim_status IN ('PENDING','VERIFICATION_REQUIRED','APPROVED') ORDER BY claim_id FOR UPDATE`, [item_id, claimantId]);
      if (existing.length) lifecycle.fail('You already have an active claim for this item');
      const [result] = await connection.query(`INSERT INTO claim (item_id,claimant_id,claim_reason,claim_status)
        VALUES (?, ?, ?, 'PENDING')`, [item_id, claimantId, claim_reason || null]);
      return { claim_id: result.insertId, item_id, claimant_id: claimantId, claim_status: 'PENDING', value_tier: item.value_tier };
    });
    return res.status(201).json({ message: 'Claim submitted successfully', claim });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to submit claim'); }
};

// ----------------------------------------------------
// GET CURRENT USER CLAIMS
// GET /api/claims/my
// ----------------------------------------------------

const getMyClaims = async (req, res) => {
  try {
    const claimantId = req.user.user_id;

    const [claims] = await pool.query(
      `
      SELECT
        c.claim_id,
        c.item_id,
        c.claim_reason,
        c.claim_status,
        c.submitted_at,
        c.reviewed_at,

        i.item_name,
        i.item_type,
        i.value_tier,
        i.location,
        i.status AS item_status

      FROM claim c

      JOIN item i
        ON c.item_id = i.item_id

      WHERE c.claimant_id = ?

      ORDER BY c.submitted_at DESC
      `,
      [claimantId]
    );

    return res.status(200).json({
      claims
    });
  } catch (error) {
    console.error('Get my claims error:', error);

    return res.status(500).json({
      message: 'Failed to load claims',
      error: error.message
    });
  }
};

// ----------------------------------------------------
// ADMIN - GET ALL CLAIMS
// GET /api/claims
// ----------------------------------------------------

const getAllClaims = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const [claims] = await pool.query(
      `
      SELECT
        c.claim_id,
        c.item_id,
        c.claimant_id,
        c.claim_reason,
        c.claim_status,
        c.submitted_at,
        c.reviewed_at,

        i.item_name,
        i.value_tier,
        i.location,
        i.status AS item_status,

        u.name AS claimant_name,
        u.email AS claimant_email

      FROM claim c

      JOIN item i
        ON c.item_id = i.item_id

      JOIN user u
        ON c.claimant_id = u.user_id

      ORDER BY c.submitted_at DESC
      `
    );

    return res.status(200).json({
      claims
    });
  } catch (error) {
    console.error('Get all claims error:', error);

    return res.status(500).json({
      message: 'Failed to load claims',
      error: error.message
    });
  }
};

module.exports = {
  createClaim,
  getMyClaims,
  getAllClaims
};