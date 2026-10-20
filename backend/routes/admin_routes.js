const express = require('express');
const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const requireAdmin =
  require('../middleware/admin_middleware');

const {
  createAdmin
} = require('../controllers/admin_controller');

router.use(authenticateToken);
router.use(requireAdmin);

router.post('/create-admin', createAdmin);

module.exports = router;