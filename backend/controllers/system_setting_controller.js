const pool = require('../config/db');


// ============================================================
// GET RETENTION SETTINGS
// GET /api/settings/retention
// ADMIN ONLY
// ============================================================

const getRetentionSetting = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const [rows] = await pool.query(
      `
      SELECT
        setting_key,
        setting_value,
        updated_by,
        updated_at
      FROM system_setting
      WHERE setting_key = 'RETENTION_PERIOD_DAYS'
      LIMIT 1
      `
    );

    if (rows.length === 0) {
      return res.status(404).json({
        message: 'Retention setting not found'
      });
    }

    return res.status(200).json({
      retention_period_days:
        Number(rows[0].setting_value),

      updated_by:
        rows[0].updated_by,

      updated_at:
        rows[0].updated_at
    });

  } catch (error) {
    console.error(
      'Get retention setting error:',
      error
    );

    return res.status(500).json({
      message:
        'Failed to retrieve retention setting',

      error:
        error.message
    });
  }
};


// ============================================================
// UPDATE RETENTION SETTINGS
// PATCH /api/settings/retention
// ADMIN ONLY
// ============================================================

const updateRetentionSetting = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message: 'Admin access required'
      });
    }

    const days = Number(
      req.body.retention_period_days
    );

    if (
      !Number.isInteger(days) ||
      days < 1 ||
      days > 365
    ) {
      return res.status(400).json({
        message:
          'Retention period must be between 1 and 365 days'
      });
    }

    await pool.query(
      `
      INSERT INTO system_setting
      (
        setting_key,
        setting_value,
        updated_by
      )
      VALUES (
        'RETENTION_PERIOD_DAYS',
        ?,
        ?
      )

      ON DUPLICATE KEY UPDATE
        setting_value = VALUES(setting_value),
        updated_by = VALUES(updated_by)
      `,
      [
        String(days),
        req.user.user_id
      ]
    );

    return res.status(200).json({
      message:
        'Retention period updated successfully',

      retention_period_days:
        days
    });

  } catch (error) {
    console.error(
      'Update retention setting error:',
      error
    );

    return res.status(500).json({
      message:
        'Failed to update retention setting',

      error:
        error.message
    });
  }
};


// ============================================================
// GET HIGH VALUE CATEGORY SETTINGS
// GET /api/settings/high-value-categories
// ADMIN ONLY
// ============================================================

const getHighValueCategories = async (req, res) => {
  try {
    if (
      req.user.role !== 'ADMIN' &&
      req.user.role !== 'SUPER_ADMIN'
    ) {
      return res.status(403).json({
        message:
          'Admin access required'
      });
    }

    const [categories] =
      await pool.query(
        `
        SELECT
          category_id,
          category_name,
          default_value_tier
        FROM item_category
        ORDER BY category_name ASC
        `
      );

    return res.status(200).json({
      categories
    });

  } catch (error) {
    console.error(
      'Get high value categories error:',
      error
    );

    return res.status(500).json({
      message:
        'Failed to load high value category settings',

      error:
        error.message
    });
  }
};


// ============================================================
// UPDATE HIGH VALUE CATEGORY SETTINGS
// PATCH /api/settings/high-value-categories
// ADMIN ONLY
// ============================================================

const updateHighValueCategories =
  async (req, res) => {

    let connection;

    try {
      if (
        req.user.role !== 'ADMIN' &&
        req.user.role !== 'SUPER_ADMIN'
      ) {
        return res.status(403).json({
          message:
            'Admin access required'
        });
      }

      const {
        high_value_category_ids
      } = req.body;

      // --------------------------------------------------------
      // VALIDATE REQUEST
      // --------------------------------------------------------

      if (
        !Array.isArray(
          high_value_category_ids
        )
      ) {
        return res.status(400).json({
          message:
            'high_value_category_ids must be an array'
        });
      }

      const categoryIds = [
        ...new Set(
          high_value_category_ids.map(
            (id) => Number(id)
          )
        )
      ];

      if (
        categoryIds.some(
          (id) =>
            !Number.isInteger(id) ||
            id <= 0
        )
      ) {
        return res.status(400).json({
          message:
            'Invalid category ID provided'
        });
      }

      // --------------------------------------------------------
      // START TRANSACTION
      // --------------------------------------------------------

      connection =
        await pool.getConnection();

      await connection.beginTransaction();

      // --------------------------------------------------------
      // GET + LOCK EXISTING CATEGORIES
      // --------------------------------------------------------

      const [existingCategories] =
        await connection.query(
          `
          SELECT
            category_id,
            category_name,
            default_value_tier
          FROM item_category
          FOR UPDATE
          `
        );

      const existingIds =
        new Set(
          existingCategories.map(
            (category) =>
              Number(
                category.category_id
              )
          )
        );

      const invalidIds =
        categoryIds.filter(
          (id) =>
            !existingIds.has(id)
        );

      if (
        invalidIds.length > 0
      ) {
        await connection.rollback();

        return res.status(400).json({
          message:
            'One or more selected categories do not exist',

          invalid_category_ids:
            invalidIds
        });
      }

      // --------------------------------------------------------
      // ALL CATEGORIES DEFAULT TO MEDIUM
      // --------------------------------------------------------

      await connection.query(
        `
        UPDATE item_category
        SET default_value_tier = 'MEDIUM'
        `
      );

      // --------------------------------------------------------
      // SELECTED CATEGORIES → HIGH
      // --------------------------------------------------------

      if (
        categoryIds.length > 0
      ) {
        const placeholders =
          categoryIds
            .map(() => '?')
            .join(',');

        await connection.query(
          `
          UPDATE item_category
          SET default_value_tier = 'HIGH'
          WHERE category_id
          IN (${placeholders})
          `,
          categoryIds
        );
      }

      // --------------------------------------------------------
      // PREPARE AUDIT DETAILS
      // --------------------------------------------------------

      const selectedCategories =
        existingCategories
          .filter(
            (category) =>
              categoryIds.includes(
                Number(
                  category.category_id
                )
              )
          )
          .map(
            (category) => ({
              category_id:
                category.category_id,

              category_name:
                category.category_name
            })
          );

      // --------------------------------------------------------
      // AUDIT LOG
      // --------------------------------------------------------

      await connection.query(
        `
        INSERT INTO audit_log
        (
          admin_id,
          item_id,
          claim_id,
          action_type,
          action_details
        )
        VALUES (
          ?,
          NULL,
          NULL,
          ?,
          ?
        )
        `,
        [
          req.user.user_id,

          'HIGH_VALUE_CLASSIFICATION_UPDATED',

          JSON.stringify({
            high_value_categories:
              selectedCategories
          })
        ]
      );

      // --------------------------------------------------------
      // COMMIT
      // --------------------------------------------------------

      await connection.commit();

      // --------------------------------------------------------
      // RETURN UPDATED SETTINGS
      // --------------------------------------------------------

      const [updatedCategories] =
        await pool.query(
          `
          SELECT
            category_id,
            category_name,
            default_value_tier
          FROM item_category
          ORDER BY category_name ASC
          `
        );

      return res.status(200).json({
        message:
          'High value classification updated successfully',

        categories:
          updatedCategories
      });

    } catch (error) {

      if (connection) {
        try {
          await connection.rollback();
        } catch (_) {}
      }

      console.error(
        'Update high value categories error:',
        error
      );

      return res.status(500).json({
        message:
          'Failed to update high value classification',

        error:
          error.message
      });

    } finally {

      if (connection) {
        connection.release();
      }
    }
  };


// ============================================================
// EXPORTS
// ============================================================

module.exports = {
  getRetentionSetting,
  updateRetentionSetting,
  getHighValueCategories,
  updateHighValueCategories
};