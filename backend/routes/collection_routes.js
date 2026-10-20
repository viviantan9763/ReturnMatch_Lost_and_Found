const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth_middleware');
const { lookupCollection, confirmCollection } = require('../controllers/collection_controller');
router.use(authenticateToken);
router.post('/lookup', lookupCollection);
router.post('/confirm', confirmCollection);
module.exports = router;
