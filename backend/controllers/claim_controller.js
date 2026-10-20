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

const createClaim = async (req, res) => {
  try {
    const claimantId = req.user.user_id;
    const { item_id, claim_reason } = req.body;

    if (!item_id) {
      return res.status(400).json({
        message: 'Item ID is required'
      });
    }

    // Check item exists
    const [items] = await pool.query(
      `
      SELECT
        item_id,
        item_name,
        item_type,
        value_tier,
        reporter_id,
        publication_status,
        status
      FROM item
      WHERE item_id = ?
      `,
      [item_id]
    );

    if (items.length === 0) {
      return res.status(404).json({
        message: 'Item not found'
      });
    }

    const item = items[0];

    // Only FOUND items can be claimed
    if (item.item_type !== 'FOUND') {
      return res.status(400).json({
        message: 'Only found items can be claimed'
      });
    }

    if (item.publication_status !== 'PUBLISHED') {
      return res.status(409).json({ message: 'Item is not published for claims' });
    }
    if (Number(item.reporter_id) === Number(claimantId)) {
      return res.status(403).json({ message: 'You cannot claim an item you reported' });
    }
    const [approvedClaims] = await pool.query(`SELECT claim_id FROM claim WHERE item_id=?
      AND claim_status IN ('APPROVED','COLLECTED') LIMIT 1`, [item_id]);
    if (approvedClaims.length) {
      return res.status(409).json({ message: 'Item already has an approved claim' });
    }
    // Prevent claiming unavailable item
    if (
      item.status === 'CLAIMED' ||
      item.status === 'COLLECTED' ||
      item.status === 'DISPOSED'
    ) {
      return res.status(400).json({
        message: 'This item is no longer available for claim'
      });
    }

    // Prevent duplicate claim by same user
    const [existingClaims] = await pool.query(
      `
      SELECT claim_id
      FROM claim
      WHERE item_id = ?
        AND claimant_id = ?
        AND claim_status IN (
          'PENDING',
          'UNDER_REVIEW',
          'VERIFICATION_REQUIRED',
          'APPROVED'
        )
      `,
      [item_id, claimantId]
    );

    if (existingClaims.length > 0) {
      return res.status(409).json({
        message: 'You already have an active claim for this item'
      });
    }

    const [result] = await pool.query(
      `
      INSERT INTO claim
      (
        item_id,
        claimant_id,
        claim_reason,
        claim_status
      )
      VALUES (?, ?, ?, 'PENDING')
      `,
      [
        item_id,
        claimantId,
        claim_reason || null
      ]
    );

    return res.status(201).json({
      message: 'Claim submitted successfully',
      claim: {
        claim_id: result.insertId,
        item_id,
        claimant_id: claimantId,
        claim_status: 'PENDING',
        value_tier: item.value_tier
      }
    });
  } catch (error) {
    console.error('Create claim error:', error);

    return res.status(500).json({
      message: 'Failed to submit claim',
      error: error.message
    });
  }
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