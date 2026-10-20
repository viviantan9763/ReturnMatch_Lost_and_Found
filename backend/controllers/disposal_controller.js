const pool = require('../config/db');

const {
  createAuditLog
} = require('../services/audit_log_service');


// ======================================================
// GET ALL DISPOSAL RECORDS
// GET /api/disposals
// ADMIN ONLY
// ======================================================

const getDisposalRecords = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const [records] = await pool.query(
      `
      SELECT
        d.disposal_id,
        d.item_id,
        d.admin_id,
        d.disposal_status,
        d.disposal_method,
        d.disposal_date,
        d.remarks,

        i.item_name,
        i.item_type,
        i.value_tier,

        u.name AS admin_name

      FROM disposal_record d

      JOIN item i
        ON d.item_id = i.item_id

      JOIN user u
        ON d.admin_id = u.user_id

      ORDER BY
        d.disposal_id DESC
      `
    );

    return res.status(200).json({
      success: true,
      count: records.length,
      records
    });

  } catch (error) {
    console.error(
      'Get disposal records error:',
      error
    );

    return res.status(500).json({
      success: false,
      message:
        'Failed to retrieve disposal records',
      error: error.message
    });
  }
};


// ======================================================
// CREATE DISPOSAL RECORD
// POST /api/disposals/:itemId
// ======================================================

const createDisposalRecord = async (req, res) => {
  const connection =
    await pool.getConnection();

  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const itemId =
      Number(req.params.itemId);

    const adminId =
      req.user.user_id;

    const {
      disposal_method,
      remarks
    } = req.body;

    const allowedMethods = [
      'RECYCLING',
      'DONATION',
      'GENERAL_DISPOSAL'
    ];

    if (
      disposal_method &&
      !allowedMethods.includes(
        disposal_method
      )
    ) {
      return res.status(400).json({
        message:
          'Invalid disposal method'
      });
    }

    await connection.beginTransaction();

    // --------------------------------------------------
    // 1. Check item
    // --------------------------------------------------

    const [items] =
      await connection.query(
        `
        SELECT
          item_id,
          item_name,
          status
        FROM item
        WHERE item_id = ?
        `,
        [itemId]
      );

    if (items.length === 0) {
      await connection.rollback();

      return res.status(404).json({
        message: 'Item not found'
      });
    }

    const item = items[0];

    // --------------------------------------------------
    // 2. Check retention record
    // --------------------------------------------------

    const [retentionRecords] =
      await connection.query(
        `
        SELECT
          retention_id,
          retention_status,
          retention_due_date
        FROM retention_record
        WHERE item_id = ?
        ORDER BY retention_id DESC
        LIMIT 1
        `,
        [itemId]
      );

    if (
      retentionRecords.length === 0
    ) {
      await connection.rollback();

      return res.status(400).json({
        message:
          'Item does not have a retention record'
      });
    }

    const retention =
      retentionRecords[0];

    if (
      retention.retention_status !==
      'DUE'
    ) {
      await connection.rollback();

      return res.status(400).json({
        message:
          'Item has not reached the retention due stage'
      });
    }

    // --------------------------------------------------
    // 3. Prevent duplicate active disposal record
    // --------------------------------------------------

    const [existing] =
      await connection.query(
        `
        SELECT disposal_id
        FROM disposal_record
        WHERE item_id = ?
          AND disposal_status IN (
            'PENDING',
            'COMPLETED'
          )
        LIMIT 1
        `,
        [itemId]
      );

    if (existing.length > 0) {
      await connection.rollback();

      return res.status(409).json({
        message:
          'A disposal record already exists for this item'
      });
    }

    // --------------------------------------------------
    // 4. Create disposal record
    // --------------------------------------------------

    const [result] =
      await connection.query(
        `
        INSERT INTO disposal_record
        (
          item_id,
          admin_id,
          disposal_status,
          disposal_method,
          remarks
        )
        VALUES (?, ?, 'PENDING', ?, ?)
        `,
        [
          itemId,
          adminId,
          disposal_method || null,
          remarks || null
        ]
      );

    // --------------------------------------------------
    // 5. Audit log
    // --------------------------------------------------

    await createAuditLog({
      admin_id: adminId,
      item_id: itemId,
      claim_id: null,
      action_type:
        'DISPOSAL_CREATED',
      action_details:
        `Disposal record created for item ${itemId} (${item.item_name}).`,
      connection
    });

    await connection.commit();

    return res.status(201).json({
      success: true,
      message:
        'Disposal record created successfully',

      disposal: {
        disposal_id:
          result.insertId,

        item_id:
          itemId,

        disposal_status:
          'PENDING',

        disposal_method:
          disposal_method || null
      }
    });

  } catch (error) {
    await connection.rollback();

    console.error(
      'Create disposal record error:',
      error
    );

    return res.status(500).json({
      success: false,
      message:
        'Failed to create disposal record',
      error: error.message
    });

  } finally {
    connection.release();
  }
};


// ======================================================
// COMPLETE / CANCEL DISPOSAL
// PATCH /api/disposals/:disposalId/status
// ======================================================

const updateDisposalStatus =
  async (req, res) => {
    const connection =
      await pool.getConnection();

    try {
      if (
        req.user.role !== 'ADMIN' &&
        req.user.role !==
          'SUPER_ADMIN'
      ) {
        return res.status(403).json({
          message:
            'Admin access required'
        });
      }

      const disposalId =
        Number(
          req.params.disposalId
        );

      const adminId =
        req.user.user_id;

      const {
        status,
        disposal_method,
        remarks
      } = req.body;

      if (
        status !== 'COMPLETED' &&
        status !== 'CANCELLED'
      ) {
        return res.status(400).json({
          message:
            'Status must be COMPLETED or CANCELLED'
        });
      }

      const allowedMethods = [
        'RECYCLING',
        'DONATION',
        'GENERAL_DISPOSAL'
      ];

      if (
        disposal_method &&
        !allowedMethods.includes(
          disposal_method
        )
      ) {
        return res.status(400).json({
          message:
            'Invalid disposal method'
        });
      }

      await connection.beginTransaction();

      // ------------------------------------------------
      // Get disposal record
      // ------------------------------------------------

      const [records] =
        await connection.query(
          `
          SELECT
            d.disposal_id,
            d.item_id,
            d.disposal_status,
            i.item_name

          FROM disposal_record d

          JOIN item i
            ON d.item_id =
               i.item_id

          WHERE d.disposal_id = ?
          `,
          [disposalId]
        );

      if (records.length === 0) {
        await connection.rollback();

        return res.status(404).json({
          message:
            'Disposal record not found'
        });
      }

      const record =
        records[0];

      if (
        record.disposal_status !==
        'PENDING'
      ) {
        await connection.rollback();

        return res.status(400).json({
          message:
            'Only pending disposal records can be updated'
        });
      }

      // ------------------------------------------------
      // Update disposal
      // ------------------------------------------------

      await connection.query(
        `
        UPDATE disposal_record

        SET
          disposal_status = ?,
          disposal_method =
            COALESCE(
              ?,
              disposal_method
            ),

          disposal_date =
            CASE
              WHEN ? = 'COMPLETED'
              THEN NOW()
              ELSE NULL
            END,

          remarks =
            COALESCE(
              ?,
              remarks
            )

        WHERE disposal_id = ?
        `,
        [
          status,
          disposal_method || null,
          status,
          remarks || null,
          disposalId
        ]
      );

      // ------------------------------------------------
      // Complete retention if disposal completed
      // ------------------------------------------------

      if (
        status === 'COMPLETED'
      ) {
        await connection.query(
          `
          UPDATE retention_record

          SET
            retention_status =
              'COMPLETED',

            checked_at = NOW()

          WHERE item_id = ?
            AND retention_status =
              'DUE'
          `,
          [
            record.item_id
          ]
        );
      }

      // ------------------------------------------------
      // Audit
      // ------------------------------------------------

      await createAuditLog({
        admin_id: adminId,
        item_id:
          record.item_id,
        claim_id: null,

        action_type:
          status === 'COMPLETED'
            ? 'DISPOSAL_COMPLETED'
            : 'DISPOSAL_CANCELLED',

        action_details:
          status === 'COMPLETED'
            ? `Disposal completed for item ${record.item_id} (${record.item_name}).`
            : `Disposal cancelled for item ${record.item_id} (${record.item_name}).`,

        connection
      });

      await connection.commit();

      return res.status(200).json({
        success: true,
        message:
          `Disposal ${status.toLowerCase()} successfully`
      });

    } catch (error) {
      await connection.rollback();

      console.error(
        'Update disposal status error:',
        error
      );

      return res.status(500).json({
        success: false,
        message:
          'Failed to update disposal record',
        error: error.message
      });

    } finally {
      connection.release();
    }
  };

  // ======================================================
// REVERSE COMPLETED DISPOSAL
// POST /api/disposals/:disposalId/reverse
// ADMIN ONLY
//
// Used only when a disposal was marked COMPLETED
// by mistake but the physical item is still held
// by the Lost & Found Office.
// ======================================================

const reverseDisposal = async (req, res) => {
  const connection = await pool.getConnection();

  try {
    // --------------------------------------------------
    // 1. Admin only
    // --------------------------------------------------
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const disposalId =
      Number(req.params.disposalId);

    const adminId =
      req.user.user_id;

    const {
      reason
    } = req.body;

    if (
      !Number.isInteger(disposalId) ||
      disposalId <= 0
    ) {
      return res.status(400).json({
        message: 'Invalid disposal ID'
      });
    }

    if (
      !reason ||
      !reason.trim()
    ) {
      return res.status(400).json({
        message:
          'Reason for reversal is required'
      });
    }

    await connection.beginTransaction();

    // --------------------------------------------------
    // 2. Get and lock disposal record
    // --------------------------------------------------
    const [records] =
      await connection.query(
        `
        SELECT
          d.disposal_id,
          d.item_id,
          d.disposal_status,
          d.disposal_method,
          d.disposal_date,

          i.item_name,
          i.item_type,
          i.custody_status

        FROM disposal_record d

        JOIN item i
          ON d.item_id = i.item_id

        WHERE d.disposal_id = ?

        FOR UPDATE
        `,
        [disposalId]
      );

    if (records.length === 0) {
      await connection.rollback();

      return res.status(404).json({
        message:
          'Disposal record not found'
      });
    }

    const record = records[0];

    // --------------------------------------------------
    // 3. Only COMPLETED disposal can be reversed
    // --------------------------------------------------
    if (
      record.disposal_status !== 'COMPLETED'
    ) {
      await connection.rollback();

      return res.status(400).json({
        message:
          'Only completed disposal records can be reversed'
      });
    }

    // Item must still logically belong to office custody
    if (
      record.custody_status !== 'RECEIVED'
    ) {
      await connection.rollback();

      return res.status(400).json({
        message:
          'Item is not currently recorded as received by the Lost & Found Office'
      });
    }

    // --------------------------------------------------
    // 4. Make sure there is no ACTIVE / DUE retention
    // --------------------------------------------------
    const [activeRetention] =
      await connection.query(
        `
        SELECT retention_id
        FROM retention_record
        WHERE item_id = ?
          AND retention_status IN (
            'ACTIVE',
            'DUE'
          )
        LIMIT 1
        `,
        [record.item_id]
      );

    if (activeRetention.length > 0) {
      await connection.rollback();

      return res.status(409).json({
        message:
          'Item already has an active retention record'
      });
    }

    // --------------------------------------------------
    // 5. Get current retention setting
    // --------------------------------------------------
    const [settings] =
      await connection.query(
        `
        SELECT setting_value
        FROM system_setting
        WHERE setting_key =
          'RETENTION_PERIOD_DAYS'
        LIMIT 1
        `
      );

    if (settings.length === 0) {
      await connection.rollback();

      return res.status(500).json({
        message:
          'Retention period has not been configured'
      });
    }

    const retentionDays =
      Number(settings[0].setting_value);

    if (
      !Number.isInteger(retentionDays) ||
      retentionDays < 1
    ) {
      await connection.rollback();

      return res.status(500).json({
        message:
          'Invalid retention period configuration'
      });
    }

    // --------------------------------------------------
    // 6. Mark old disposal as REVERSED
    // --------------------------------------------------
    await connection.query(
      `
      UPDATE disposal_record
      SET
        disposal_status = 'REVERSED',
        remarks = CASE
          WHEN remarks IS NULL
            OR remarks = ''
          THEN ?
          ELSE CONCAT(
            remarks,
            '\\nReversal: ',
            ?
          )
        END
      WHERE disposal_id = ?
      `,
      [
        reason.trim(),
        reason.trim(),
        disposalId
      ]
    );

    // --------------------------------------------------
    // 7. Create NEW retention record
    // Do not reopen/overwrite old completed retention.
    // --------------------------------------------------
    const [retentionResult] =
      await connection.query(
        `
        INSERT INTO retention_record
        (
          item_id,
          retention_start_date,
          retention_due_date,
          retention_status
        )
        VALUES
        (
          ?,
          CURDATE(),
          DATE_ADD(
            CURDATE(),
            INTERVAL ? DAY
          ),
          'ACTIVE'
        )
        `,
        [
          record.item_id,
          retentionDays
        ]
      );

    // --------------------------------------------------
    // 8. Audit disposal reversal
    // --------------------------------------------------
    await createAuditLog({
      admin_id: adminId,
      item_id: record.item_id,
      claim_id: null,
      action_type:
        'DISPOSAL_REVERSED',
      action_details:
        `Completed disposal ${disposalId} was reversed. Reason: ${reason.trim()}`,
      connection
    });

    // --------------------------------------------------
    // 9. Audit new retention period
    // --------------------------------------------------
    await createAuditLog({
      admin_id: adminId,
      item_id: record.item_id,
      claim_id: null,
      action_type:
        'RETENTION_REOPENED',
      action_details:
        `A new ${retentionDays}-day retention period was started after disposal reversal.`,
      connection
    });

    // --------------------------------------------------
    // 10. Read newly-created retention record
    // --------------------------------------------------
    const [newRetention] =
      await connection.query(
        `
        SELECT
          retention_id,
          item_id,
          retention_start_date,
          retention_due_date,
          retention_status
        FROM retention_record
        WHERE retention_id = ?
        `,
        [retentionResult.insertId]
      );

    await connection.commit();

    return res.status(200).json({
      success: true,

      message:
        'Disposal reversed and item restored to retention successfully',

      disposal: {
        disposal_id: disposalId,
        item_id: record.item_id,
        disposal_status: 'REVERSED'
      },

      retention_period_days:
        retentionDays,

      retention:
        newRetention[0]
    });

  } catch (error) {
    try {
      await connection.rollback();
    } catch (_) {}

    console.error(
      'Reverse disposal error:',
      error
    );

    return res.status(500).json({
      success: false,
      message:
        'Failed to reverse disposal',
      error: error.message
    });

  } finally {
    connection.release();
  }
};

module.exports = {
  getDisposalRecords,
  createDisposalRecord,
  updateDisposalStatus,
  reverseDisposal
};