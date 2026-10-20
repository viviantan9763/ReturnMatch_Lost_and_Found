// ReturnMatch - backend/controllers/item_controller.js
// Full controller based on the existing project code.
// Automatic value-tier classification uses item_category.default_value_tier.
// HIGH-value reports wait for Admin publication review.
// Automatic AI matching is a separate Phase 3B feature (not triggered here).

const pool = require('../config/db');
const { createAuditLog } = require('../services/audit_log_service');

const cleanText = (value) =>
  typeof value === 'string' ? value.trim() : '';

const isAdmin = (user) =>
  user && (user.role === 'ADMIN' || user.role === 'SUPER_ADMIN');

// =====================================================
// CREATE ITEM
// POST /api/items
// =====================================================
const createItem = async (req, res) => {
  try {
    const reporterId = req.user.user_id;
    const {
      security_questions,
      category_id,
      item_name,
      model_info,
      colour,
      description,
      item_type,
      location,
      event_date
    } = req.body;

    const normalizedItemType = cleanText(item_type).toUpperCase();
    const normalizedItemName = cleanText(item_name);
    const normalizedModelInfo = cleanText(model_info);
    const normalizedColour = cleanText(colour) || null;
    const normalizedDescription = cleanText(description) || null;
    const normalizedLocation = cleanText(location) || null;

    // 1. Basic validation
    if (
      !normalizedItemName ||
      !['LOST', 'FOUND'].includes(normalizedItemType) ||
      category_id === undefined ||
      category_id === null ||
      category_id === ''
    ) {
      return res.status(400).json({
        message: 'Item name, category and valid item type are required'
      });
    }

    const normalizedCategoryId = Number(category_id);
    if (!Number.isInteger(normalizedCategoryId) || normalizedCategoryId <= 0) {
      return res.status(400).json({ message: 'Invalid category ID' });
    }

    // 2. Get category and its administrator-configured default value tier
    const [categories] = await pool.query(
      `
      SELECT category_id, category_name, default_value_tier
      FROM item_category
      WHERE category_id = ?
      LIMIT 1
      `,
      [normalizedCategoryId]
    );

    if (categories.length === 0) {
      return res.status(400).json({
        message: 'Selected category does not exist'
      });
    }

    const category = categories[0];
    const categoryName = category.category_name;
    const categoryKey = cleanText(categoryName).toLowerCase();

    // 3. Model is required only for LOST electronics.
    // FOUND reports can omit the model; users may enter "Unknown" for LOST.
    const modelRequired =
      normalizedItemType === 'LOST' &&
      ['mobile phone', 'laptop', 'tablet'].includes(categoryKey);

    if (modelRequired && !normalizedModelInfo) {
      return res.status(400).json({
        message: 'Please enter the model or "Unknown" for this lost item'
      });
    }

    // 4. Rule-based value classification from category.
    // CLIP can suggest a category via the separate AI endpoint.
    // This is not an independent ML value-prediction model.
    const valueTier =
      category.default_value_tier === 'HIGH' ? 'HIGH' : 'MEDIUM';

    const custodyStatus =
      normalizedItemType === 'FOUND' ? 'NOT_RECEIVED' : null;

    // Found reports must carry two independent private ownership checks.
    // Do not accept or publish answers in public item endpoints.
    if (normalizedItemType === 'FOUND') {
      if (!Array.isArray(security_questions) || security_questions.length !== 2) {
        return res.status(400).json({
          message: 'Please provide exactly two private ownership questions and answers'
        });
      }
      const questions = security_questions.map((q) => ({
        question: cleanText(q?.question),
        answer: cleanText(q?.answer)
      }));
      if (questions.some(q => q.question.length < 8 || q.question.length > 250 ||
        q.answer.length < 2 || q.answer.length > 250)) {
        return res.status(400).json({
          message: 'Questions must be 8–250 characters; answers must be 2–250 characters'
        });
      }
      if (questions[0].question.toLowerCase() === questions[1].question.toLowerCase()) {
        return res.status(400).json({message: 'Use two different ownership questions'});
      }
    }

    // Preserve existing publication workflow: HIGH requires review.
    const publicationStatus =
      valueTier === 'HIGH' ? 'PENDING_REVIEW' : 'PUBLISHED';

    // Insert item and security questions atomically.
    const connection = await pool.getConnection();
    let result;
    try {
      await connection.beginTransaction();
      [result] = await connection.query(
      `
      INSERT INTO item (
        reporter_id,
        category_id,
        item_name,
        model_info,
        colour,
        description,
        item_type,
        value_tier,
        status,
        publication_status,
        custody_status,
        location,
        storage_location,
        event_date
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE', ?, ?, ?, NULL, ?)
      `,
      [
        reporterId,
        normalizedCategoryId,
        normalizedItemName,
        normalizedModelInfo || null,
        normalizedColour,
        normalizedDescription,
        normalizedItemType,
        valueTier,
        publicationStatus,
        custodyStatus,
        normalizedLocation,
        event_date || null
      ]
    );

      if (normalizedItemType === 'FOUND') {
        for (let index = 0; index < security_questions.length; index++) {
          const question = security_questions[index];
          await connection.query(
            `INSERT INTO item_security_question
             (item_id, question_no, question_text, answer_hash)
             VALUES (?, ?, ?, SHA2(LOWER(TRIM(?)), 256))`,
            [result.insertId, index + 1, cleanText(question.question), cleanText(question.answer)]
          );
        }
      }
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    return res.status(201).json({
      message: 'Item reported successfully',
      item: {
        item_id: result.insertId,
        reporter_id: reporterId,
        category_id: normalizedCategoryId,
        category_name: categoryName,
        item_name: normalizedItemName,
        model_info: normalizedModelInfo || null,
        colour: normalizedColour,
        description: normalizedDescription,
        item_type: normalizedItemType,
        value_tier: valueTier,
        status: 'ACTIVE',
        publication_status: publicationStatus,
        custody_status: custodyStatus,
        location: normalizedLocation,
        storage_location: null,
        event_date: event_date || null
      }
    });
  } catch (error) {
    console.error('Create item error:', error);
    return res.status(500).json({
      message: 'Failed to report item',
      error: error.message
    });
  }
};

// =====================================================
// GET ITEM CATEGORIES
// GET /api/items/categories
// =====================================================
const getItemCategories = async (req, res) => {
  try {
    const [categories] = await pool.query(
      `
      SELECT category_id, category_name
      FROM item_category
      ORDER BY category_name ASC
      `
    );

    return res.status(200).json({ categories });
  } catch (error) {
    console.error('Get item categories error:', error);
    return res.status(500).json({
      message: 'Failed to load item categories',
      error: error.message
    });
  }
};

// =====================================================
// VIEW PERMISSIONS
// Admin sees all. Reporter sees their own pending/rejected reports.
// Other users only see published and available reports.
// High-value FOUND reports hide identifying details from other users.
// =====================================================
const canViewItem = (item, user) =>
  isAdmin(user) ||
  Number(item.reporter_id) === Number(user.user_id) ||
  (item.publication_status === 'PUBLISHED' &&
    ['ACTIVE', 'MATCHED', 'CLAIM_PENDING'].includes(item.status));

const sanitizeItemForViewer = (item, user) => {
  const safe = { ...item };
  const privileged =
    isAdmin(user) || Number(safe.reporter_id) === Number(user.user_id);

  // Operational review metadata and storage details are not public data.
  if (!isAdmin(user)) {
    safe.storage_location = null;
    delete safe.publication_reviewed_by;
  }
  if (!privileged) {
    delete safe.publication_review_note;
    delete safe.publication_reviewed_at;
    safe.reporter_id = null;
    safe.reporter_name = null;
  }

  if (!privileged && safe.item_type === 'FOUND' && safe.value_tier === 'HIGH') {
    // Prevent claimants learning unique ownership evidence from public listings.
    safe.item_name = safe.category_name || 'High-value found item';
    safe.model_info = null;
    safe.colour = null;
    safe.description = null;
  }
  return safe;
};

// =====================================================
// GET ALL ITEMS
// GET /api/items
// =====================================================
const getAllItems = async (req, res) => {
  try {
    const [items] = await pool.query(
      `
      SELECT
        i.item_id, i.reporter_id, i.category_id,
        c.category_name,
        i.item_name, i.model_info, i.colour, i.description,
        i.item_type, i.value_tier, i.status, i.publication_status,
        i.custody_status, i.location, i.storage_location,
        i.event_date, i.reported_at,
        u.name AS reporter_name
      FROM item i
      JOIN user u ON i.reporter_id = u.user_id
      LEFT JOIN item_category c ON i.category_id = c.category_id
      WHERE
        (i.publication_status = 'PUBLISHED'
         AND i.status IN ('ACTIVE', 'MATCHED', 'CLAIM_PENDING'))
        OR i.reporter_id = ?
        OR ? = 1
      ORDER BY i.reported_at DESC
      `,
      [req.user.user_id, isAdmin(req.user) ? 1 : 0]
    );

    return res.status(200).json({
      message: 'Items retrieved successfully',
      count: items.length,
      items: items.map(item => sanitizeItemForViewer(item, req.user))
    });
  } catch (error) {
    console.error('Get items error:', error);
    return res.status(500).json({ message: 'Failed to retrieve items' });
  }
};

// =====================================================
// GET ONE ITEM
// GET /api/items/:id
// =====================================================
const getItemById = async (req, res) => {
  try {
    const itemId = Number(req.params.id);
    if (!Number.isInteger(itemId) || itemId <= 0) {
      return res.status(400).json({ message: 'Invalid item ID' });
    }

    const [items] = await pool.query(
      `
      SELECT i.*, c.category_name, u.name AS reporter_name
      FROM item i
      JOIN user u ON i.reporter_id = u.user_id
      LEFT JOIN item_category c ON i.category_id = c.category_id
      WHERE i.item_id = ?
      `,
      [itemId]
    );

    if (!items.length || !canViewItem(items[0], req.user)) {
      return res.status(404).json({ message: 'Item not found' });
    }

    return res.status(200).json({
      message: 'Item retrieved successfully',
      item: sanitizeItemForViewer(items[0], req.user)
    });
  } catch (error) {
    console.error('Get item error:', error);
    return res.status(500).json({ message: 'Failed to retrieve item' });
  }
};

// =====================================================
// UPDATE INDIVIDUAL ITEM VALUE TIER
// Admin override: MEDIUM <-> HIGH
// Note: the provided item_routes.js does not expose this route yet.
// =====================================================
const updateItemValueTier = async (req, res) => {
  if (!isAdmin(req.user)) {
    return res.status(403).json({ message: 'Admin access required' });
  }

  const itemId = Number(req.params.id);
  const newTier = cleanText(req.body?.value_tier).toUpperCase();
  if (!Number.isInteger(itemId) || itemId <= 0) {
    return res.status(400).json({ message: 'Invalid item ID' });
  }
  if (!['MEDIUM', 'HIGH'].includes(newTier)) {
    return res.status(400).json({ message: 'Value tier must be MEDIUM or HIGH' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [items] = await connection.query(
      `SELECT item_id, reporter_id, item_name, value_tier, status, publication_status
       FROM item WHERE item_id = ? FOR UPDATE`,
      [itemId]
    );
    if (!items.length) {
      await connection.rollback();
      return res.status(404).json({ message: 'Item not found' });
    }

    const item = items[0];
    if (item.status !== 'ACTIVE') {
      await connection.rollback();
      return res.status(409).json({ message: 'Only ACTIVE items can change value tier' });
    }
    if (item.value_tier === newTier) {
      await connection.rollback();
      return res.status(200).json({
        message: 'Value tier unchanged', item_id: itemId,
        value_tier: newTier, publication_status: item.publication_status
      });
    }

    // Reclassifying MEDIUM -> HIGH withdraws the report from public listing.
    // Reclassifying HIGH -> MEDIUM automatically publishes it.
    const publicationStatus =
      newTier === 'HIGH' ? 'PENDING_REVIEW' : 'PUBLISHED';
    await connection.query(`
      UPDATE item
      SET value_tier = ?, publication_status = ?,
          publication_reviewed_by = NULL,
          publication_reviewed_at = NULL,
          publication_review_note = NULL
      WHERE item_id = ?
    `, [newTier, publicationStatus, itemId]);

    await createAuditLog({
      admin_id: req.user.user_id,
      item_id: itemId,
      claim_id: null,
      action_type: 'ITEM_VALUE_TIER_CHANGED',
      action_details:
        `Item ${itemId} (${item.item_name}) changed from ${item.value_tier} to ${newTier}.`,
      connection
    });

    await connection.query(`
      INSERT INTO notification
        (user_id, item_id, claim_id, notification_type, message)
      VALUES (?, ?, NULL, 'VALUE_TIER_CHANGED', ?)
    `, [item.reporter_id, itemId,
      newTier === 'HIGH'
        ? `Your report #${itemId} was classified HIGH and now requires Admin publication review.`
        : `Your report #${itemId} was classified MEDIUM and has been published.`
    ]);

    await connection.commit();
    return res.status(200).json({
      message: 'Item value tier updated successfully',
      item_id: itemId, value_tier: newTier,
      publication_status: publicationStatus
    });
  } catch (error) {
    try { await connection.rollback(); } catch (_) {}
    console.error('Update item value tier error:', error);
    return res.status(500).json({
      message: 'Failed to update value tier. Check audit_log action_type compatibility.'
    });
  } finally {
    connection.release();
  }
};

// =====================================================
// UPLOAD ITEM IMAGE
// POST /api/items/:id/images
// =====================================================
const uploadItemImage = async (req, res) => {
  const itemId = Number(req.params.id);
  if (!req.file) {
    return res.status(400).json({ message: 'Image file is required' });
  }
  if (!Number.isInteger(itemId) || itemId <= 0) {
    return res.status(400).json({ message: 'Invalid item ID' });
  }
  if (!req.file.filename) {
    return res.status(500).json({
      message: 'Upload middleware must save the file on disk (filename missing)'
    });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    const [items] = await connection.query(
      `SELECT item_id, reporter_id, status, value_tier, publication_status
       FROM item WHERE item_id = ? FOR UPDATE`,
      [itemId]
    );

    if (!items.length) {
      await connection.rollback();
      return res.status(404).json({ message: 'Item not found' });
    }
    const item = items[0];
    if (Number(item.reporter_id) !== Number(req.user.user_id) && !isAdmin(req.user)) {
      await connection.rollback();
      return res.status(403).json({
        message: 'You are not allowed to upload images for this item'
      });
    }
    if (item.status !== 'ACTIVE' || item.publication_status === 'REJECTED') {
      await connection.rollback();
      return res.status(409).json({
        message: 'Images cannot be changed for this item in its current state'
      });
    }

    const [existingImages] = await connection.query(
      'SELECT image_id FROM item_image WHERE item_id = ? LIMIT 1',
      [itemId]
    );
    const imageRole = existingImages.length ? 'ADDITIONAL' : 'PRIMARY';
    const imagePath = `uploads/${req.file.filename}`;

    const [result] = await connection.query(
      `INSERT INTO item_image (item_id, image_path, image_role)
       VALUES (?, ?, ?)`,
      [itemId, imagePath, imageRole]
    );

    let publicationStatus = item.publication_status;
    // If new evidence is added to an approved HIGH report, require re-review.
    if (item.value_tier === 'HIGH' && item.publication_status === 'PUBLISHED') {
      publicationStatus = 'PENDING_REVIEW';
      await connection.query(`
        UPDATE item
        SET publication_status = 'PENDING_REVIEW',
            publication_reviewed_by = NULL,
            publication_reviewed_at = NULL,
            publication_review_note = NULL
        WHERE item_id = ?
      `, [itemId]);
    }

    await connection.commit();
    return res.status(201).json({
      message: 'Image uploaded successfully',
      image: {
        image_id: result.insertId,
        item_id: itemId,
        image_path: imagePath,
        image_role: imageRole
      },
      publication_status: publicationStatus
    });
  } catch (error) {
    try { await connection.rollback(); } catch (_) {}
    console.error('Upload item image error:', error);
    return res.status(500).json({ message: 'Failed to upload image' });
  } finally {
    connection.release();
  }
};

// =====================================================
// CONFIRM FOUND ITEM RECEIVED BY LOST & FOUND OFFICE
// PATCH /api/items/:id/receive (ADMIN ONLY)
// =====================================================
const confirmItemReceived = async (req, res) => {
  const connection = await pool.getConnection();

  try {
    if (!isAdmin(req.user)) {
      return res.status(403).json({ message: 'Admin access required' });
    }

    const itemId = Number(req.params.id);
    const adminId = req.user.user_id;
    const storageLocation = cleanText(req.body.storage_location);

    if (!Number.isInteger(itemId) || itemId <= 0) {
      return res.status(400).json({ message: 'Invalid item ID' });
    }

    if (!storageLocation) {
      return res.status(400).json({
        message: 'Storage location is required'
      });
    }

    await connection.beginTransaction();

    // 1. Lock item row
    const [items] = await connection.query(
      `
      SELECT item_id, item_name, item_type, status, custody_status
      FROM item
      WHERE item_id = ?
      FOR UPDATE
      `,
      [itemId]
    );

    if (items.length === 0) {
      await connection.rollback();
      return res.status(404).json({ message: 'Item not found' });
    }

    const item = items[0];
    if (item.item_type !== 'FOUND') {
      await connection.rollback();
      return res.status(400).json({
        message: 'Only FOUND items can be received into Lost & Found custody'
      });
    }

    if (item.custody_status === 'RECEIVED') {
      await connection.rollback();
      return res.status(409).json({
        message: 'This item has already been received by the Lost & Found Office'
      });
    }

    if (item.custody_status !== 'NOT_RECEIVED') {
      await connection.rollback();
      return res.status(400).json({
        message: 'Item is not currently awaiting office receipt'
      });
    }

    // 2. Prevent duplicate active retention records
    const [existingRetention] = await connection.query(
      `
      SELECT retention_id
      FROM retention_record
      WHERE item_id = ?
        AND retention_status IN ('ACTIVE', 'DUE')
      LIMIT 1
      `,
      [itemId]
    );

    if (existingRetention.length > 0) {
      await connection.rollback();
      return res.status(409).json({
        message: 'A retention record already exists for this item'
      });
    }

    // 3. Read retention period
    const [settings] = await connection.query(
      `
      SELECT setting_value
      FROM system_setting
      WHERE setting_key = 'RETENTION_PERIOD_DAYS'
      LIMIT 1
      `
    );

    if (settings.length === 0) {
      await connection.rollback();
      return res.status(500).json({
        message: 'Retention period has not been configured'
      });
    }

    const retentionDays = Number(settings[0].setting_value);
    if (!Number.isInteger(retentionDays) || retentionDays < 1) {
      await connection.rollback();
      return res.status(500).json({
        message: 'Invalid retention period configuration'
      });
    }

    // 4. Update physical custody
    await connection.query(
      `
      UPDATE item
      SET custody_status = 'RECEIVED', storage_location = ?
      WHERE item_id = ?
      `,
      [storageLocation, itemId]
    );

    // 5. Start retention
    const [retentionResult] = await connection.query(
      `
      INSERT INTO retention_record (
        item_id, retention_start_date, retention_due_date, retention_status
      )
      VALUES (
        ?, CURDATE(), DATE_ADD(CURDATE(), INTERVAL ? DAY), 'ACTIVE'
      )
      `,
      [itemId, retentionDays]
    );

    // 6. Audit actions in the same transaction
    await createAuditLog({
      admin_id: adminId,
      item_id: itemId,
      claim_id: null,
      action_type: 'ITEM_RECEIVED',
      action_details:
        `Found item ${itemId} (${item.item_name}) received by Lost & Found Office and stored at ${storageLocation}.`,
      connection
    });

    await createAuditLog({
      admin_id: adminId,
      item_id: itemId,
      claim_id: null,
      action_type: 'RETENTION_STARTED',
      action_details:
        `Retention started automatically for ${retentionDays} day(s).`,
      connection
    });

    // 7. Fetch newly created retention record
    const [retentionRecords] = await connection.query(
      `
      SELECT retention_id, item_id, retention_start_date,
             retention_due_date, retention_status
      FROM retention_record
      WHERE retention_id = ?
      `,
      [retentionResult.insertId]
    );

    await connection.commit();

    return res.status(200).json({
      message: 'Item received and retention started successfully',
      item: {
        item_id: itemId,
        item_name: item.item_name,
        custody_status: 'RECEIVED',
        storage_location: storageLocation
      },
      retention_period_days: retentionDays,
      retention: retentionRecords[0]
    });
  } catch (error) {
    try {
      await connection.rollback();
    } catch (_) {}

    console.error('Confirm item received error:', error);
    return res.status(500).json({
      message: 'Failed to confirm item receipt',
      error: error.message
    });
  } finally {
    connection.release();
  }
};

module.exports = {
  getItemCategories,
  createItem,
  getAllItems,
  getItemById,
  updateItemValueTier,
  uploadItemImage,
  confirmItemReceived
};
