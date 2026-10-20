// ReturnMatch: real MySQL notifications, scoped to the authenticated user.
// Table: notification(notification_id, user_id, item_id, claim_id,
//                     notification_type, message, is_read, created_at)

const pool = require('../config/db');

function currentUserId(req, res) {
  const userId = Number(req.user && req.user.user_id);
  if (!Number.isSafeInteger(userId) || userId <= 0) {
    res.status(401).json({ success: false, message: 'Please log in again.' });
    return null;
  }
  return userId;
}

// GET /api/notifications?limit=50
exports.getMyNotifications = async (req, res) => {
  const userId = currentUserId(req, res);
  if (userId === null) return;

  const requestedLimit = Number(req.query.limit ?? 50);
  const limit = Number.isSafeInteger(requestedLimit)
    ? Math.max(1, Math.min(requestedLimit, 100))
    : 50;

  try {
    const [notifications] = await pool.query(
      `SELECT notification_id, user_id, item_id, claim_id,
              notification_type, message, is_read, created_at
         FROM notification
        WHERE user_id = ?
        ORDER BY created_at DESC, notification_id DESC
        LIMIT ?`,
      [userId, limit]
    );

    const [[counter]] = await pool.query(
      `SELECT COUNT(*) AS unread_count
         FROM notification
        WHERE user_id = ? AND is_read = 0`,
      [userId]
    );

    return res.status(200).json({
      success: true,
      notifications,
      unread_count: Number(counter.unread_count)
    });
  } catch (error) {
    console.error('Get notifications error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to load notifications.'
    });
  }
};

// PATCH /api/notifications/read-all
exports.markAllAsRead = async (req, res) => {
  const userId = currentUserId(req, res);
  if (userId === null) return;

  try {
    const [result] = await pool.query(
      `UPDATE notification
          SET is_read = 1
        WHERE user_id = ? AND is_read = 0`,
      [userId]
    );
    return res.status(200).json({
      success: true,
      message: 'All notifications marked as read.',
      updated_count: result.affectedRows
    });
  } catch (error) {
    console.error('Mark all notifications read error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to update notifications.'
    });
  }
};

// PATCH /api/notifications/:id/read
exports.markAsRead = async (req, res) => {
  const userId = currentUserId(req, res);
  if (userId === null) return;

  const notificationId = Number(req.params.id);
  if (!Number.isSafeInteger(notificationId) || notificationId <= 0) {
    return res.status(400).json({
      success: false,
      message: 'Invalid notification ID.'
    });
  }

  try {
    const [result] = await pool.query(
      `UPDATE notification
          SET is_read = 1
        WHERE notification_id = ? AND user_id = ?`,
      [notificationId, userId]
    );

    if (result.affectedRows === 0) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found.'
      });
    }
    return res.status(200).json({
      success: true,
      message: 'Notification marked as read.'
    });
  } catch (error) {
    console.error('Mark notification read error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to update notification.'
    });
  }
};
