const bcrypt = require('bcrypt');
const pool = require('../config/db');
const jwt = require('jsonwebtoken');

const register = async (req, res) => {
  try {
    const { name, email, password, phone_no } = req.body;

    // 1. Check required fields
    if (!name || !email || !password) {
      return res.status(400).json({
        message: 'Name, email and password are required'
      });
    }

    // 2. Check whether email already exists
    const [existingUsers] = await pool.query(
      'SELECT user_id FROM user WHERE email = ?',
      [email]
    );

    if (existingUsers.length > 0) {
      return res.status(409).json({
        message: 'Email is already registered'
      });
    }

    // 3. Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // 4. Save user into MySQL
    const [result] = await pool.query(
      `INSERT INTO user
       (name, email, password_hash, role, phone_no)
       VALUES (?, ?, ?, 'USER', ?)`,
      [name, email, passwordHash, phone_no || null]
    );

    // 5. Return successful response
    return res.status(201).json({
      message: 'Registration successful',
      user: {
        user_id: result.insertId,
        name,
        email,
        role: 'USER'
      }
    });

  } catch (error) {
    console.error('Register error:', error);

    return res.status(500).json({
      message: 'Internal server error'
    });
  }
};

const login = async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        message: 'Email and password are required'
      });
    }

    const [users] = await pool.query(
      `SELECT user_id, name, email, password_hash, role, account_status
       FROM user
       WHERE email = ?`,
      [email]
    );

    if (users.length === 0) {
      return res.status(401).json({
        message: 'Invalid email or password'
      });
    }

    const user = users[0];

    if (user.account_status !== 'ACTIVE') {
      return res.status(403).json({
        message: 'Account is not active'
      });
    }

    const passwordCorrect = await bcrypt.compare(
      password,
      user.password_hash
    );

    if (!passwordCorrect) {
      return res.status(401).json({
        message: 'Invalid email or password'
      });
    }

    const token = jwt.sign(
      {
        user_id: user.user_id,
        role: user.role
      },
      process.env.JWT_SECRET,
      {
        expiresIn: '1h'
      }
    );

    return res.status(200).json({
      message: 'Login successful',
      token,
      user: {
        user_id: user.user_id,
        name: user.name,
        email: user.email,
        role: user.role
      }
    });

  } catch (error) {
    console.error('Login error:', error);

    return res.status(500).json({
      message: 'Internal server error'
    });
  }
};

module.exports = {
  register,
  login
};