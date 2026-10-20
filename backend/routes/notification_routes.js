const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth_middleware');
const {
  getMyNotifications,
  markAsRead,
  markAllAsRead
} = require('../controllers/notification_controller');

// Students, staff and admins can only read THEIR OWN notifications.
router.use(authenticateToken);
router.get('/', getMyNotifications);
router.patch('/read-all', markAllAsRead);
router.patch('/:id/read', markAsRead);

module.exports = router;
