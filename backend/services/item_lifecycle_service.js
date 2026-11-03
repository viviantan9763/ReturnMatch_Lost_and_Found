const pool = require('../config/db');
const { createAuditLog } = require('./audit_log_service');

const available = item => ['ACTIVE', 'MATCHED', 'CLAIM_PENDING'].includes(item.status);
const inCustody = item => item.custody_status === 'RECEIVED' &&
  typeof item.storage_location === 'string' && item.storage_location.trim().length > 0;
function fail(message, status = 409) {
  const error = new Error(message);
  error.status = status;
  throw error;
}
function changed(result) {
  if (result.affectedRows !== 1) fail('Item state changed. Refresh before trying again.');
}

// Every lifecycle writer locks the item first. Never retry an unknown commit
// outcome: staff must refresh before attempting another physical handover.
async function withItem(itemId, work) {
  let connection;
  try {
    connection = await pool.getConnection();
    await connection.beginTransaction();
    const [items] = await connection.query('SELECT * FROM item WHERE item_id = ? FOR UPDATE', [itemId]);
    if (!items.length) fail('Item not found', 404);
    const result = await work(connection, items[0]);
    await connection.commit();
    return result;
  } catch (error) {
    if (connection) { try { await connection.rollback(); } catch (_) {} }
    if (['ER_LOCK_DEADLOCK', 'ER_LOCK_WAIT_TIMEOUT'].includes(error.code)) {
      fail('Concurrent item action. Refresh and try again.', 409);
    }
    throw error;
  } finally { if (connection) connection.release(); }
}

async function resolveItem(table, key, id) {
  // table/key are internal constants, never request input.
  const [rows] = await pool.query(`SELECT item_id FROM ${table} WHERE ${key} = ?`, [id]);
  if (!rows.length) fail(table === 'claim' ? 'Claim not found' : 'Disposal record not found', 404);
  return rows[0].item_id;
}

async function disposals(connection, itemId) {
  const [rows] = await connection.query(
    'SELECT * FROM disposal_record WHERE item_id = ? ORDER BY disposal_id FOR UPDATE', [itemId]);
  return rows;
}
async function claims(connection, itemId) {
  const [rows] = await connection.query(
    'SELECT * FROM claim WHERE item_id = ? ORDER BY claim_id FOR UPDATE', [itemId]);
  return rows;
}
async function retentions(connection, itemId) {
  const [rows] = await connection.query(`SELECT *, retention_due_date <= CURDATE() AS is_due
    FROM retention_record WHERE item_id = ? ORDER BY retention_id FOR UPDATE`, [itemId]);
  return rows;
}
const openRetentions = rows => rows.filter(r => ['ACTIVE', 'DUE'].includes(r.retention_status));
const blockingDisposals = rows => rows.filter(d => ['PENDING', 'COMPLETED'].includes(d.disposal_status));
const blockingClaims = rows => rows.filter(c => c.claim_status !== 'REJECTED');
function requireOfficeItem(item) {
  if (item.item_type !== 'FOUND' || !inCustody(item)) {
    fail('Confirm office receipt and storage location before this action.');
  }
}
function requireCollectible(item, claim, disposalRows) {
  requireOfficeItem(item);
  if (!available(item) || claim.claim_status !== 'APPROVED' || blockingDisposals(disposalRows).length) {
    fail('Claim or item is not eligible for collection.');
  }
}
async function withCollectibleClaim(claimId, work) {
  const itemId = await resolveItem('claim', 'claim_id', claimId);
  return withItem(itemId, async (connection, item) => {
    const claimRows = await claims(connection, itemId);
    const claim = claimRows.find(c => Number(c.claim_id) === Number(claimId));
    if (!claim) fail('Claim changed. Refresh before trying again.');
    if (claimRows.some(c => Number(c.claim_id) !== Number(claimId) && ['APPROVED','COLLECTED'].includes(c.claim_status))) {
      fail('Item has another successful ownership claim. Manual review is required.');
    }
    requireCollectible(item, claim, await disposals(connection, itemId));
    return work(connection, item, claim);
  });
}
async function expireOtps(connection, itemId) {
  await connection.query(`UPDATE claim_otp o JOIN claim c ON c.claim_id = o.claim_id
    SET o.otp_status = 'EXPIRED', o.expired_at = NOW()
    WHERE c.item_id = ? AND o.otp_status = 'ACTIVE'`, [itemId]);
}
async function audit(connection, adminId, itemId, action, details, claimId = null) {
  await createAuditLog({ connection, admin_id: adminId, item_id: itemId, claim_id: claimId,
    action_type: action, action_details: details });
}
async function markDue(connection, item, retention, adminId) {
  if (!Number(retention.is_due)) fail('Retention due date has not been reached.');
  if (retention.retention_status === 'ACTIVE') {
    const [result] = await connection.query(`UPDATE retention_record SET retention_status = 'DUE', checked_at = NOW()
      WHERE retention_id = ? AND retention_status = 'ACTIVE' AND retention_due_date <= CURDATE()`, [retention.retention_id]);
    changed(result);
    await audit(connection, adminId, item.item_id, 'RETENTION_DUE', `Retention ${retention.retention_id} reached its due date.`);
    retention.retention_status = 'DUE';
    return true;
  }
  return false;
}
async function retentionDays(connection) {
  const [rows] = await connection.query("SELECT setting_value FROM system_setting WHERE setting_key = 'RETENTION_PERIOD_DAYS' LIMIT 1");
  const days = Number(rows[0]?.setting_value);
  if (!Number.isInteger(days) || days < 1 || days > 365) fail('Invalid retention period configuration', 500);
  return days;
}
async function collect(claimId, code, adminId) {
  return withCollectibleClaim(claimId, async (connection, item) => {
    const [otps] = await connection.query(`SELECT otp_id FROM claim_otp WHERE claim_id = ? AND otp_code = ?
      AND otp_status = 'ACTIVE' AND expired_at > NOW() ORDER BY otp_id FOR UPDATE`, [claimId, code]);
    if (otps.length !== 1) fail('Invalid, expired, or ambiguous OTP', 400);
    const retentionRows = openRetentions(await retentions(connection, item.item_id));
    const [otpResult] = await connection.query(`UPDATE claim_otp SET otp_status = 'USED', used_at = NOW()
      WHERE otp_id = ? AND otp_status = 'ACTIVE' AND expired_at > NOW()`, [otps[0].otp_id]);
    changed(otpResult);
    const [claimResult] = await connection.query("UPDATE claim SET claim_status = 'COLLECTED' WHERE claim_id = ? AND claim_status = 'APPROVED'", [claimId]);
    changed(claimResult);
    const [itemResult] = await connection.query(`UPDATE item SET status = 'CLAIMED', custody_status = NULL, storage_location = NULL
      WHERE item_id = ? AND status = ? AND custody_status = 'RECEIVED'`, [item.item_id, item.status]);
    changed(itemResult);
    for (const r of retentionRows) {
      const [result] = await connection.query(`UPDATE retention_record SET retention_status = 'COMPLETED', checked_at = NOW()
        WHERE retention_id = ? AND retention_status IN ('ACTIVE','DUE')`, [r.retention_id]);
      changed(result);
      await audit(connection, adminId, item.item_id, 'RETENTION_COMPLETED', `Retention ${r.retention_id} closed on collection.`, claimId);
    }
    await expireOtps(connection, item.item_id);
    await audit(connection, adminId, item.item_id, 'CLAIM_COLLECTED',
      `Claim ${claimId} handed over using OTP. Previous custody: ${item.custody_status}; storage: ${item.storage_location}.`, claimId);
    return { claim_id: Number(claimId), claim_status: 'COLLECTED', item_id: item.item_id, item_status: 'CLAIMED' };
  });
}
function respondError(res, error, fallback) {
  if (!error.status) console.error(fallback, error.code || error.message);
  return res.status(error.status || 500).json({ success: false, message: error.status ? error.message : fallback });
}
module.exports = { available, inCustody, fail, changed, withItem, resolveItem, disposals, claims, retentions,
  openRetentions, blockingDisposals, blockingClaims, requireOfficeItem, requireCollectible,
  withCollectibleClaim, expireOtps, audit, markDue, retentionDays, collect, respondError };
