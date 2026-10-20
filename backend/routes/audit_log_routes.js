const express = require('express');

const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getAuditLogs
} = require('../controllers/audit_log_controller');


// All audit log routes require login
router.use(authenticateToken);


// GET /api/audit-logs
router.get(
  '/',
  getAuditLogs
);


module.exports = router;