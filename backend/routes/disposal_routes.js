const express =
  require('express');

const router =
  express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getDisposalRecords,
  createDisposalRecord,
  updateDisposalStatus,
  reverseDisposal
} = require(
  '../controllers/disposal_controller'
);

router.use(
  authenticateToken
);


// GET all records
router.get(
  '/',
  getDisposalRecords
);


// Create disposal record
router.post(
  '/:itemId',
  createDisposalRecord
);


// Complete / cancel
router.patch(
  '/:disposalId/status',
  updateDisposalStatus
);


// Reverse a completed disposal
router.post(
  '/:disposalId/reverse',
  reverseDisposal
);

module.exports = router;