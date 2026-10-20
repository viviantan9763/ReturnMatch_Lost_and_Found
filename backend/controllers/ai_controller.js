
const axios = require('axios');
const FormData = require('form-data');

const analyzeImage = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        message: 'Image file is required'
      });
    }

    const aiServiceUrl =
      process.env.AI_SERVICE_URL ||
      'http://127.0.0.1:8001';

    // Convert uploaded image into multipart/form-data
    const form = new FormData();

    form.append('file', req.file.buffer, {
      filename: req.file.originalname || 'item.jpg',
      contentType: req.file.mimetype
    });

    // Forward image to Python FastAPI
    const response = await axios.post(
      `${aiServiceUrl}/analyze-image`,
      form,
      {
        headers: form.getHeaders(),
        timeout: 120000,
        maxBodyLength: 11 * 1024 * 1024
      }
    );

    // Return actual CLIP + BLIP results to frontend
    return res.status(200).json(response.data);

  } catch (error) {
    console.error(
      'AI image analysis error:',
      error.message
    );

    // Forward validation errors from FastAPI
    if (
      error.response &&
      error.response.status >= 400 &&
      error.response.status < 500
    ) {
      return res.status(error.response.status).json({
        message: 'AI image validation failed',
        detail: error.response.data?.detail || null
      });
    }

    return res.status(502).json({
      message:
        'AI service is unavailable or image analysis failed'
    });
  }
};

module.exports = {
  analyzeImage
};
