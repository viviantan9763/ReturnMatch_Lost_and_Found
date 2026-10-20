const pool = require('../config/db');

const {
  createAuditLog
} = require('../services/audit_log_service');


// =====================================================
// GET ALL RETENTION RECORDS
// GET /api/retention
// ADMIN ONLY
//
// ACTIVE records automatically become DUE
// when the retention due date is reached.
// =====================================================
const getRetentionRecords = async (req, res) => {
  const connection = await pool.getConnection();

  try {
    // -------------------------------------------------
    // 1. Admin only
    // -------------------------------------------------
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const adminId = req.user.user_id;

    await connection.beginTransaction();

    // -------------------------------------------------
    // 2. Find ACTIVE retention records that are due
    // -------------------------------------------------
    const [dueRecords] = await connection.query(
      `
      SELECT
        r.retention_id,
        r.item_id,
        r.retention_due_date,
        i.item_name

      FROM retention_record r

      JOIN item i
        ON r.item_id = i.item_id

      WHERE r.retention_status = 'ACTIVE'
        AND r.retention_due_date <= CURDATE()

      FOR UPDATE
      `
    );

    // -------------------------------------------------
    // 3. Automatically change ACTIVE -> DUE
    // -------------------------------------------------
    if (dueRecords.length > 0) {
      await connection.query(
        `
        UPDATE retention_record
        SET
          retention_status = 'DUE',
          checked_at = NOW()

        WHERE retention_status = 'ACTIVE'
          AND retention_due_date <= CURDATE()
        `
      );

      // -----------------------------------------------
      // 4. Audit every automatic DUE transition
      // -----------------------------------------------
      for (const record of dueRecords) {
        await createAuditLog({
          admin_id: adminId,
          item_id: record.item_id,
          claim_id: null,
          action_type: 'RETENTION_DUE',
          action_details:
            `Retention period reached its due date for item ${record.item_id} (${record.item_name}).`,
          connection
        });
      }
    }

    // -------------------------------------------------
    // 5. Load retention records
    // -------------------------------------------------
    const [records] = await connection.query(
      `
      SELECT
        r.retention_id,
        r.item_id,
        r.retention_start_date,
        r.retention_due_date,
        r.retention_status,
        r.checked_at,

        i.item_name,
        i.item_type,
        i.value_tier,
        i.status AS item_status,
        i.custody_status,
        i.location,
        i.storage_location

      FROM retention_record r

      JOIN item i
        ON r.item_id = i.item_id

      ORDER BY
        CASE r.retention_status
          WHEN 'DUE' THEN 1
          WHEN 'ACTIVE' THEN 2
          WHEN 'COMPLETED' THEN 3
        END,
        r.retention_due_date ASC
      `
    );

    await connection.commit();

    return res.status(200).json({
      success: true,
      count: records.length,
      newly_due_count: dueRecords.length,
      records
    });

  } catch (error) {
    try {
      await connection.rollback();
    } catch (_) {}

    console.error(
      'Get retention records error:',
      error
    );

    return res.status(500).json({
      success: false,
      message: 'Failed to load retention records',
      error: error.message
    });

  } finally {
    connection.release();
  }
};


module.exports = {
  getRetentionRecords
};