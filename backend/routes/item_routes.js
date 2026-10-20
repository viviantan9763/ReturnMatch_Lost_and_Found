// ReturnMatch - backend/routes/item_routes.js
const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth_middleware');
const upload = require('../middleware/upload_middleware');

const {
  createItem,
  getAllItems,
  getItemCategories,
  getItemById,
  updateItemValueTier,
  uploadItemImage,
  confirmItemReceived
} = require('../controllers/item_controller');

const {
  getPendingHighValueReports,
  reviewHighValueReport
} = require('../controllers/item_publication_controller');

router.use(authenticateToken);

// Static routes before dynamic /:id
router.get('/categories', getItemCategories);
router.get('/review-queue', getPendingHighValueReports); // ADMIN only in controller

router.post('/', createItem);
router.get('/', getAllItems);
router.get('/:id', getItemById);

router.post('/:id/images', upload.single('image'), uploadItemImage);
router.patch('/:id/publication', reviewHighValueReport); // ADMIN only
router.patch('/:id/value-tier', updateItemValueTier);   // ADMIN only
router.patch('/:id/receive', confirmItemReceived);     // ADMIN only

module.exports = router;
