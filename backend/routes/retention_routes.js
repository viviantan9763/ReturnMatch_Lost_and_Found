const express = require('express');

const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getRetentionRecords
} = require(
  '../controllers/retention_controller'
);

router.use(authenticateToken);

// Get all retention records
// Also automatically checks ACTIVE -> DUE
router.get(
  '/',
  getRetentionRecords
);

module.exports = router;