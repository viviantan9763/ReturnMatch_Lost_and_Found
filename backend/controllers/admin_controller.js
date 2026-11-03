const bcrypt = require('bcrypt');
const pool = require('../config/db');
const { passwordPolicyError } = require('../utils/password_policy');

const createAdmin = async (req, res) => {
  if (!req.user || req.user.role !== 'SUPER_ADMIN') {
    return res.status(403).json({ message: 'Super Admin access required' });
  }

  try {
    const { name, email, password, phone_no } = req.body || {};

    if (!name || !email || !password) {
      return res.status(400).json({
        message: 'Name, email and password are required'
      });
    }

    const passwordError = passwordPolicyError(password);
    if (passwordError) {
      return res.status(400).json({ message: passwordError });
    }

    const [existingUsers] = await pool.query(
      'SELECT user_id FROM user WHERE email = ?',
      [email]
    );

    if (existingUsers.length > 0) {
      return res.status(409).json({
        message: 'Email is already registered'
      });
    }

    const passwordHash = await bcrypt.hash(password, 10);

    const [result] = await pool.query(
      `
      INSERT INTO user
      (name, email, password_hash, role, phone_no)
      VALUES (?, ?, ?, 'ADMIN', ?)
      `,
      [
        name,
        email,
        passwordHash,
        phone_no || null
      ]
    );

    return res.status(201).json({
      message: 'Administrator account created successfully',
      admin: {
        user_id: result.insertId,
        name,
        email,
        role: 'ADMIN'
      }
    });
  } catch (error) {
    console.error('Create admin error:', error);

    return res.status(500).json({
      message: 'Failed to create administrator',
      error: error.message
    });
  }
};

module.exports = {
  createAdmin
};
