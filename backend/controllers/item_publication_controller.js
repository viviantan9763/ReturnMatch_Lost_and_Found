// ReturnMatch - backend/controllers/item_publication_controller.js
// Phase 3A: Admin review of HIGH-value lost/found reports only.

const pool = require('../config/db');
const { createAuditLog } = require('../services/audit_log_service');

const isAdmin = (user) =>
  Boolean(user && ['ADMIN', 'SUPER_ADMIN'].includes(user.role));

const cleanText = (value) =>
  typeof value === 'string' ? value.trim() : '';

// GET /api/items/review-queue
// HIGH-value reports only; MEDIUM reports publish automatically.
const getPendingHighValueReports = async (req, res) => {
  if (!isAdmin(req.user)) {
    return res.status(403).json({ message: 'Admin access required' });
  }

  try {
    const [items] = await pool.query(`
      SELECT
        i.item_id, i.reporter_id, u.name AS reporter_name,
        i.category_id, c.category_name,
        i.item_name, i.model_info, i.colour, i.description,
        i.item_type, i.value_tier, i.status, i.publication_status,
        i.location, i.event_date, i.reported_at,
        (
          SELECT ii.image_path
          FROM item_image ii
          WHERE ii.item_id = i.item_id
          ORDER BY (ii.image_role = 'PRIMARY') DESC, ii.uploaded_at ASC
          LIMIT 1
        ) AS image_path
      FROM item i
      JOIN user u ON u.user_id = i.reporter_id
      LEFT JOIN item_category c ON c.category_id = i.category_id
      WHERE i.value_tier = 'HIGH'
        AND i.status = 'ACTIVE'
        AND i.publication_status = 'PENDING_REVIEW'
      ORDER BY i.reported_at ASC
      LIMIT 100
    `);

    return res.status(200).json({ count: items.length, items });
  } catch (error) {
    console.error('Get high-value review queue error:', error);
    return res.status(500).json({ message: 'Failed to load review queue' });
  }
};

// PATCH /api/items/:id/publication
// Body: { "decision": "APPROVED" | "REJECTED", "review_note": "..." }
const reviewHighValueReport = async (req, res) => {
  if (!isAdmin(req.user)) {
    return res.status(403).json({ message: 'Admin access required' });
  }

  const itemId = Number(req.params.id);
  const decision = cleanText(req.body?.decision).toUpperCase();
  const reviewNote = cleanText(req.body?.review_note);

  if (!Number.isInteger(itemId) || itemId <= 0) {
    return res.status(400).json({ message: 'Invalid item ID' });
  }
  if (!['APPROVED', 'REJECTED'].includes(decision)) {
    return res.status(400).json({ message: 'Decision must be APPROVED or REJECTED' });
  }
  if (decision === 'REJECTED' && !reviewNote) {
    return res.status(400).json({ message: 'A review note is required for rejection' });
  }
  if (reviewNote.length > 500) {
    return res.status(400).json({ message: 'Review note must be 500 characters or fewer' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const [rows] = await connection.query(`
      SELECT item_id, reporter_id, item_name, item_type,
             value_tier, status, publication_status
      FROM item
      WHERE item_id = ?
      FOR UPDATE
    `, [itemId]);

    if (!rows.length) {
      await connection.rollback();
      return res.status(404).json({ message: 'Item not found' });
    }

    const item = rows[0];
    if (item.value_tier !== 'HIGH') {
      await connection.rollback();
      return res.status(400).json({
        message: 'Only HIGH-value reports require publication review'
      });
    }
    if (item.status !== 'ACTIVE') {
      await connection.rollback();
      return res.status(409).json({ message: 'Only ACTIVE reports can be reviewed' });
    }
    if (item.publication_status !== 'PENDING_REVIEW') {
      await connection.rollback();
      return res.status(409).json({ message: 'Report has already been reviewed' });
    }

    // Images are optional at publication time. AI image matching will be
    // skipped until a report has an image; text-only review remains possible.
    const publicationStatus = decision === 'APPROVED' ? 'PUBLISHED' : 'REJECTED';

    await connection.query(`
      UPDATE item
      SET publication_status = ?,
          publication_reviewed_by = ?,
          publication_reviewed_at = NOW(),
          publication_review_note = ?
      WHERE item_id = ?
    `, [publicationStatus, req.user.user_id, reviewNote || null, itemId]);

    // Important: verify audit_log.action_type supports these values.
    // If it is an ENUM that does not, the transaction rolls back safely.
    await createAuditLog({
      admin_id: req.user.user_id,
      item_id: itemId,
      claim_id: null,
      action_type: decision === 'APPROVED' ? 'REPORT_APPROVED' : 'REPORT_REJECTED',
      action_details: `HIGH-value ${item.item_type} report ${itemId} (${item.item_name}) ${decision.toLowerCase()}.${reviewNote ? ` Note: ${reviewNote}` : ''}`,
      connection
    });

    await connection.query(`
      INSERT INTO notification
        (user_id, item_id, claim_id, notification_type, message)
      VALUES (?, ?, NULL, ?, ?)
    `, [
      item.reporter_id,
      itemId,
      decision === 'APPROVED' ? 'REPORT_APPROVED' : 'REPORT_REJECTED',
      decision === 'APPROVED'
        ? `Your high-value ${item.item_type.toLowerCase()} report #${itemId} is now published.`
        : `Your high-value ${item.item_type.toLowerCase()} report #${itemId} was rejected.${reviewNote ? ` Reason: ${reviewNote}` : ''}`
    ]);

    await connection.commit();
    return res.status(200).json({
      message: `Report ${decision.toLowerCase()} successfully`,
      item_id: itemId,
      publication_status: publicationStatus,
      reviewed_by: req.user.user_id
    });
  } catch (error) {
    try { await connection.rollback(); } catch (_) {}
    console.error('Review high-value report error:', error);
    return res.status(500).json({
      message: 'Failed to review report. Check audit_log action_type compatibility.'
    });
  } finally {
    connection.release();
  }
};

module.exports = { getPendingHighValueReports, reviewHighValueReport };
