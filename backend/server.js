require('dotenv').config();

const express = require('express');
const cors = require('cors');
const pool = require('./config/db');
const authRoutes = require('./routes/auth_routes');
const itemRoutes = require('./routes/item_routes');
const adminRoutes = require('./routes/admin_routes');
const claimRoutes = require('./routes/claim_routes');
const profileRoutes = require('./routes/profile_routes');
const notificationRoutes = require('./routes/notification_routes');
const retentionRoutes = require('./routes/retention_routes');
const matchRoutes =require('./routes/match_routes');
const auditLogRoutes = require('./routes/audit_log_routes');
const disposalRoutes = require('./routes/disposal_routes');
const systemSettingRoutes = require('./routes/system_setting_routes');
const aiRoutes = require('./routes/ai_routes');
const collectionRoutes = require('./routes/collection_routes');


const app = express();

app.use(cors());
app.use(express.json());
app.use('/api/auth', authRoutes);
app.use('/api/items', itemRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/claims', claimRoutes);
app.use('/api/profile', profileRoutes);
app.use('/api/notifications',notificationRoutes);
app.use('/api/retention',retentionRoutes);
app.use('/api/matches',matchRoutes);
app.use('/api/audit-logs',auditLogRoutes);
app.use('/api/disposals',disposalRoutes);
app.use('/api/settings',systemSettingRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/collection', collectionRoutes);


app.get('/', (req, res) => {
  res.json({
    message: 'ReturnMatch backend is running'
  });
});

app.get('/api/test-db', async (req, res) => {
  try {
    const [rows] = await pool.query(
      'SELECT DATABASE() AS databaseName, NOW() AS serverTime'
    );

    res.json({
      message: 'Database connection successful',
      database: rows[0].databaseName,
      serverTime: rows[0].serverTime
    });

  } catch (error) {
    console.error(error);

    res.status(500).json({
      message: 'Database connection failed',
      error: error.message
    });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`ReturnMatch backend running on port ${PORT}`);
});