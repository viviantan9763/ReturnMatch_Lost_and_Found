const express = require('express');
const router = express.Router();

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  getProfile,
  updateProfile,
  changePassword
} = require('../controllers/profile_controller');

router.use(authenticateToken);

router.get('/', getProfile);
router.patch('/', updateProfile);
router.patch('/password', changePassword);

module.exports = router;