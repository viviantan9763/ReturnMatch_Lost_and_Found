const db = require('../config/db');

// ==========================================
// GET ALL AUDIT LOGS - ADMIN ONLY
// GET /api/audit-logs
// ==========================================
exports.getAuditLogs = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        success: false,
        message: 'Admin access required'
      });
    }

    const [logs] = await db.query(`
      SELECT
        al.log_id,
        al.admin_id,
        al.item_id,
        al.claim_id,
        al.action_type,
        al.action_details,
        al.timestamp,

        u.name AS admin_name,
        i.item_name,

        c.claim_status,
        c.claim_reason,
        c.submitted_at,
        c.reviewed_at,
        c.approved_at

      FROM audit_log al

      LEFT JOIN user u
        ON al.admin_id = u.user_id

      LEFT JOIN item i
        ON al.item_id = i.item_id

      LEFT JOIN claim c
        ON al.claim_id = c.claim_id

      ORDER BY al.timestamp DESC
    `);

    return res.status(200).json({
      success: true,
      count: logs.length,
      logs
    });

  } catch (error) {
    console.error(
      'Get audit logs error:',
      error
    );

    return res.status(500).json({
      success: false,
      message: 'Failed to retrieve audit logs',
      error: error.message
    });
  }
};