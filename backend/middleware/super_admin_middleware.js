const requireSuperAdmin = (req, res, next) => {
  if (!req.user || req.user.role !== 'SUPER_ADMIN') {
    return res.status(403).json({
      message: 'Super Admin access required'
    });
  }

  next();
};

module.exports = requireSuperAdmin;
