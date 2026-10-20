const express = require('express');

const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getHighValueCategories,
  updateHighValueCategories,
  getRetentionSetting,
  updateRetentionSetting
} = require(
  '../controllers/system_setting_controller'
);

router.use(authenticateToken);

router.get(
  '/retention',
  getRetentionSetting
);

router.patch(
  '/retention',
  updateRetentionSetting
);

router.get(
  '/high-value-categories',
  getHighValueCategories
);

router.patch(
  '/high-value-categories',
  updateHighValueCategories
);

module.exports = router;