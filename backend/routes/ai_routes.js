
const express = require('express');
const multer = require('multer');

const authenticateToken =
  require('../middleware/auth_middleware');

const {
  analyzeImage
} = require('../controllers/ai_controller');

const router = express.Router();

// Keep image in memory for temporary AI analysis
const upload = multer({
  storage: multer.memoryStorage(),

  limits: {
    fileSize: 10 * 1024 * 1024,
    files: 1
  },

  fileFilter: (req, file, callback) => {
    const allowedTypes = [
      'image/jpeg',
      'image/png',
      'image/webp'
    ];

    if (!allowedTypes.includes(file.mimetype)) {
      return callback(
        new Error(
          'Only JPEG, PNG and WEBP images are allowed'
        )
      );
    }

    callback(null, true);
  }
});

router.use(authenticateToken);

router.post(
  '/analyze-image',

  (req, res, next) => {
    upload.single('image')(req, res, (error) => {
      if (error) {
        const status =
          error.code === 'LIMIT_FILE_SIZE'
            ? 413
            : 400;

        return res.status(status).json({
          message: error.message
        });
      }

      next();
    });
  },

  analyzeImage
);

module.exports = router;
