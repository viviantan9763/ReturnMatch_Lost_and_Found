const express = require('express');
const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const requireSuperAdmin =
  require('../middleware/super_admin_middleware');

const {
  createAdmin
} = require('../controllers/admin_controller');

router.use(authenticateToken);

router.post('/create-admin', requireSuperAdmin, createAdmin);

module.exports = router;
