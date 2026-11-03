const multer = require('multer');
// Authorize and validate before creating a permanent file in the controller.
module.exports = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.mimetype)) return cb(new Error('Only JPG, PNG and WEBP images are allowed'));
    cb(null, true);
  }
});
