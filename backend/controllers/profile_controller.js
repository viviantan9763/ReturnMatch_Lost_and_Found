const bcrypt = require('bcrypt');
const pool = require('../config/db');

const getProfile = async (req, res) => {
  try {
    const userId = req.user.user_id;

    const [users] = await pool.query(
      `
      SELECT
        user_id,
        name,
        email,
        role,
        phone_no,
        account_status,
        created_at
      FROM user
      WHERE user_id = ?
      `,
      [userId]
    );

    if (users.length === 0) {
      return res.status(404).json({
        message: 'User not found'
      });
    }

    return res.status(200).json({
      user: users[0]
    });
  } catch (error) {
    console.error('Get profile error:', error);

    return res.status(500).json({
      message: 'Failed to load profile',
      error: error.message
    });
  }
};


const updateProfile = async (req, res) => {
  try {
    const userId = req.user.user_id;
    const { name, phone_no } = req.body;

    if (!name) {
      return res.status(400).json({
        message: 'Name is required'
      });
    }

    await pool.query(
      `
      UPDATE user
      SET
        name = ?,
        phone_no = ?
      WHERE user_id = ?
      `,
      [
        name,
        phone_no || null,
        userId
      ]
    );

    return res.status(200).json({
      message: 'Profile updated successfully'
    });
  } catch (error) {
    console.error('Update profile error:', error);

    return res.status(500).json({
      message: 'Failed to update profile',
      error: error.message
    });
  }
};


const changePassword = async (req, res) => {
  try {
    const userId = req.user.user_id;

    const {
      current_password,
      new_password
    } = req.body;

    if (!current_password || !new_password) {
      return res.status(400).json({
        message: 'Current and new password are required'
      });
    }

    const [users] = await pool.query(
      `
      SELECT password_hash
      FROM user
      WHERE user_id = ?
      `,
      [userId]
    );

    if (users.length === 0) {
      return res.status(404).json({
        message: 'User not found'
      });
    }

    const correct = await bcrypt.compare(
      current_password,
      users[0].password_hash
    );

    if (!correct) {
      return res.status(400).json({
        message: 'Current password is incorrect'
      });
    }

    const newHash = await bcrypt.hash(
      new_password,
      10
    );

    await pool.query(
      `
      UPDATE user
      SET password_hash = ?
      WHERE user_id = ?
      `,
      [
        newHash,
        userId
      ]
    );

    return res.status(200).json({
      message: 'Password changed successfully'
    });
  } catch (error) {
    console.error('Change password error:', error);

    return res.status(500).json({
      message: 'Failed to change password',
      error: error.message
    });
  }
};


module.exports = {
  getProfile,
  updateProfile,
  changePassword
};