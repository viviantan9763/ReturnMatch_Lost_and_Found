const pool = require('../config/db');

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
};