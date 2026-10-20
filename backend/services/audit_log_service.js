const pool = require('../config/db');

const createAuditLog = async ({
  admin_id,
  item_id = null,
  claim_id = null,
  action_type,
  action_details = null,
  connection = null
}) => {
  const db = connection || pool;

  try {
    await db.query(
      `
      INSERT INTO audit_log
      (
        admin_id,
        item_id,
        claim_id,
        action_type,
        action_details
      )
      VALUES (?, ?, ?, ?, ?)
      `,
      [
        admin_id,
        item_id,
        claim_id,
        action_type,
        action_details
      ]
    );
  } catch (error) {
    console.error(
      'Audit log error:',
      error
    );

    // Important:
    // Let controller know audit logging failed
    throw error;
  }
};

module.exports = {
  createAuditLog
};