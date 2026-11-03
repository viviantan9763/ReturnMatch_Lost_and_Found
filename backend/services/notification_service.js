// Shared notification helper for Claim and other backend controllers.
const pool = require('../config/db');

/**
 * Creates one notification. Pass an existing transaction connection when needed.
 * @param {object} options
 * @returns {Promise<number>} new notification ID
 */
async function createNotification({ user_id, item_id = null, claim_id = null,
  notification_type, message, connection = null }) {
  const userId = Number(user_id);
  if (!Number.isSafeInteger(userId) || userId <= 0) {
    throw new Error('createNotification: valid user_id is required');
  }
  if (typeof notification_type !== 'string' || !notification_type.trim() ||
      notification_type.length > 50) {
    throw new Error('createNotification: notification_type must be 1-50 characters');
  }
  if (typeof message !== 'string' || !message.trim()) {
    throw new Error('createNotification: message is required');
  }
  const db = connection || pool;
  const [result] = await db.query(
    `INSERT INTO notification (user_id, item_id, claim_id, notification_type, message)
     VALUES (?, ?, ?, ?, ?)`,
    [userId, item_id, claim_id, notification_type.trim(), message.trim()]
  );
  return result.insertId;
}

module.exports = { createNotification };
/* const pool = require('../config/db');

const createNotification = async ({
  user_id,
  item_id = null,
  claim_id = null,
  notification_type,
  message
}) => {
  try {
    await pool.query(
      `
      INSERT INTO notification
      (
        user_id,
        item_id,
        claim_id,
        notification_type,
        message
      )
      VALUES (?, ?, ?, ?, ?)
      `,
      [
        user_id,
        item_id,
        claim_id,
        notification_type,
        message
      ]
    );
  } catch (error) {
    console.error(
      'Create notification error:',
      error
    );
  }
};

module.exports = {
  createNotification
};   */