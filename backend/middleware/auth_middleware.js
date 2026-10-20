const jwt = require('jsonwebtoken');

const authenticateToken = (req, res, next) => {
  try {
    const authHeader = req.headers['authorization'];

    if (!authHeader) {
      return res.status(401).json({
        message: 'Access token is required'
      });
    }

    const token = authHeader.split(' ')[1];

    if (!token) {
      return res.status(401).json({
        message: 'Invalid authorization format'
      });
    }

    jwt.verify(
      token,
      process.env.JWT_SECRET,
      (error, decodedUser) => {
        if (error) {
          return res.status(403).json({
            message: 'Invalid or expired token'
          });
        }

        req.user = decodedUser;

        next();
      }
    );
  } catch (error) {
    console.error('Authentication middleware error:', error);

    return res.status(500).json({
      message: 'Authentication failed'
    });
  }
};

module.exports = authenticateToken;