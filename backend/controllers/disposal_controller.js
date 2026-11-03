const pool = require('../config/db');
const lifecycle = require('../services/item_lifecycle_service');
const isAdmin = u => u && ['ADMIN', 'SUPER_ADMIN'].includes(u.role);
const methods = ['RECYCLING', 'DONATION', 'GENERAL_DISPOSAL'];
const idOK = id => Number.isSafeInteger(Number(id)) && Number(id) > 0;
const text = value => typeof value === 'string' ? value.trim() : '';

// Read-side flags are hints; every write rechecks under the item lock.
const getDisposalRecords = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  try {
    const [records] = await pool.query(`SELECT d.*, i.item_name, i.item_type, i.value_tier,
      i.status AS item_status, i.custody_status, i.storage_location, u.name AS admin_name,
      (SELECT COUNT(*) FROM claim c WHERE c.item_id=d.item_id AND c.claim_status <> 'REJECTED') AS blocking_claim_count,
      (SELECT COUNT(*) FROM retention_record r WHERE r.item_id=d.item_id AND r.retention_status IN ('ACTIVE','DUE')) AS open_retention_count,
      (SELECT COUNT(*) FROM retention_record r WHERE r.item_id=d.item_id AND r.retention_status='DUE' AND r.retention_due_date<=CURDATE()) AS due_retention_count,
      (SELECT x.retention_status FROM retention_record x WHERE x.item_id=d.item_id ORDER BY x.retention_id DESC LIMIT 1) AS latest_retention_status,
      (SELECT MAX(x.disposal_id) FROM disposal_record x WHERE x.item_id=d.item_id) AS latest_disposal_id,
      (SELECT COUNT(*) FROM disposal_record x WHERE x.item_id=d.item_id AND x.disposal_status IN ('PENDING','COMPLETED')) AS live_disposal_count
      FROM disposal_record d JOIN item i ON i.item_id=d.item_id JOIN user u ON u.user_id=d.admin_id
      ORDER BY d.disposal_id DESC`);
    for (const row of records) {
      const common = row.item_type === 'FOUND' && !Number(row.blocking_claim_count) &&
        Number(row.latest_disposal_id) === Number(row.disposal_id) && Number(row.live_disposal_count) === 1;
      row.can_update = common && row.disposal_status === 'PENDING' && row.item_status === 'EXPIRED' &&
        lifecycle.inCustody(row) && Number(row.open_retention_count) === 1 && Number(row.due_retention_count) === 1;
      row.can_reverse = common && row.disposal_status === 'COMPLETED' && row.item_status === 'DISPOSED' &&
        !Number(row.open_retention_count) && row.latest_retention_status === 'COMPLETED';
      row.lifecycle_block_reason = row.can_update || row.can_reverse ? null :
        'Record is historical or its item/claim/retention state requires review.';
    }
    return res.json({ success: true, count: records.length, records });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to retrieve disposal records'); }
};

function requireUnclaimed(claimRows) {
  if (lifecycle.blockingClaims(claimRows).length) lifecycle.fail('Unresolved or successful ownership claims prevent disposal.');
}
function requireCurrentDisposal(rows, id, status) {
  const record = rows.find(row => Number(row.disposal_id) === Number(id));
  if (!record) lifecycle.fail('Disposal record changed. Refresh before trying again.');
  if (record.disposal_status !== status || Number(rows[rows.length - 1]?.disposal_id) !== Number(id) ||
      lifecycle.blockingDisposals(rows).length !== 1) {
    lifecycle.fail('Disposal is no longer the current applicable record.');
  }
  return record;
}
function requireOpenRetention(rows) {
  const open = lifecycle.openRetentions(rows);
  if (open.length !== 1 || open[0].retention_id !== rows[rows.length - 1]?.retention_id) {
    lifecycle.fail('Exactly one current retention cycle is required. Review retention history.');
  }
  return open[0];
}
const createDisposalRecord = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  if (!idOK(req.params.itemId)) return res.status(400).json({ message: 'Invalid item ID' });
  const method = req.body?.disposal_method || null;
  if (method !== null && !methods.includes(method)) return res.status(400).json({ message: 'Invalid disposal method' });
  try {
    const disposal = await lifecycle.withItem(Number(req.params.itemId), async (connection, item) => {
      lifecycle.requireOfficeItem(item);
      if (!lifecycle.available(item)) lifecycle.fail('Item is no longer available for disposal.');
      requireUnclaimed(await lifecycle.claims(connection, item.item_id));
      if (lifecycle.blockingDisposals(await lifecycle.disposals(connection, item.item_id)).length) {
        lifecycle.fail('A pending or completed disposal already exists for this item.');
      }
      const retention = requireOpenRetention(await lifecycle.retentions(connection, item.item_id));
      await lifecycle.markDue(connection, item, retention, req.user.user_id);
      const [result] = await connection.query(`INSERT INTO disposal_record
        (item_id,admin_id,disposal_status,disposal_method,remarks) VALUES (?,?,'PENDING',?,?)`,
      [item.item_id, req.user.user_id, method, text(req.body?.remarks) || null]);
      const [updated] = await connection.query("UPDATE item SET status = 'EXPIRED' WHERE item_id = ? AND status = ?",
        [item.item_id, item.status]);
      lifecycle.changed(updated);
      await lifecycle.expireOtps(connection, item.item_id);
      await lifecycle.audit(connection, req.user.user_id, item.item_id, 'DISPOSAL_CREATED',
        `Disposal ${result.insertId} reserved item: ${item.status} -> EXPIRED; retention ${retention.retention_id}.`);
      return { disposal_id: result.insertId, item_id: item.item_id, admin_id: req.user.user_id,
        disposal_status: 'PENDING', disposal_method: method };
    });
    return res.status(201).json({ success: true, message: 'Disposal record created successfully', disposal });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to create disposal record'); }
};
const updateDisposalStatus = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  const status = req.body?.status;
  const method = req.body?.disposal_method;
  if (!idOK(req.params.disposalId) || !['COMPLETED', 'CANCELLED'].includes(status) ||
      (method != null && !methods.includes(method))) {
    return res.status(400).json({ message: 'Valid disposal ID, status and method are required' });
  }
  try {
    const itemId = await lifecycle.resolveItem('disposal_record', 'disposal_id', Number(req.params.disposalId));
    await lifecycle.withItem(itemId, async (connection, item) => {
      lifecycle.requireOfficeItem(item);
      if (item.status !== 'EXPIRED') lifecycle.fail('Item is not reserved for disposal.');
      requireUnclaimed(await lifecycle.claims(connection, itemId));
      const record = requireCurrentDisposal(await lifecycle.disposals(connection, itemId), req.params.disposalId, 'PENDING');
      const retention = requireOpenRetention(await lifecycle.retentions(connection, itemId));
      if (retention.retention_status !== 'DUE' || !Number(retention.is_due)) lifecycle.fail('Retention is not due.');
      const effectiveMethod = method || record.disposal_method;
      if (status === 'COMPLETED' && !methods.includes(effectiveMethod)) lifecycle.fail('Disposal method is required before completion.', 400);
      const [updated] = await connection.query(`UPDATE disposal_record SET disposal_status = ?,
        disposal_method = ?, disposal_date = CASE WHEN ? = 'COMPLETED' THEN NOW() ELSE disposal_date END,
        remarks = CONCAT_WS('\n', NULLIF(remarks,''), ?)
        WHERE disposal_id = ? AND disposal_status = 'PENDING'`,
      [status, effectiveMethod, status, text(req.body?.remarks) || null, record.disposal_id]);
      lifecycle.changed(updated);
      const [itemResult] = await connection.query(status === 'COMPLETED'
        ? "UPDATE item SET status = 'DISPOSED', custody_status = NULL, storage_location = NULL WHERE item_id = ? AND status = 'EXPIRED'"
        : "UPDATE item SET status = 'ACTIVE' WHERE item_id = ? AND status = 'EXPIRED'", [itemId]);
      lifecycle.changed(itemResult);
      if (status === 'COMPLETED') {
        const [retResult] = await connection.query(`UPDATE retention_record SET retention_status = 'COMPLETED', checked_at = NOW()
          WHERE retention_id = ? AND retention_status = 'DUE'`, [retention.retention_id]);
        lifecycle.changed(retResult);
        await lifecycle.expireOtps(connection, itemId);
        await lifecycle.audit(connection, req.user.user_id, itemId, 'RETENTION_COMPLETED', `Retention ${retention.retention_id} closed on disposal.`);
      }
      await lifecycle.audit(connection, req.user.user_id, itemId, `DISPOSAL_${status}`,
        `Disposal ${record.disposal_id}: item EXPIRED -> ${status === 'COMPLETED' ? 'DISPOSED' : 'ACTIVE'}; ` +
        `method ${effectiveMethod || 'unset'}; previous custody ${item.custody_status}; storage ${item.storage_location}.`);
    });
    return res.json({ success: true, message: `Disposal ${status.toLowerCase()} successfully` });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to update disposal record'); }
};
const reverseDisposal = async (req, res) => {
  if (!isAdmin(req.user)) return res.status(403).json({ message: 'Admin access required' });
  const reason = text(req.body?.reason);
  const storage = text(req.body?.storage_location);
  if (!idOK(req.params.disposalId) || !reason || !storage || req.body?.confirm_item_still_held !== true) {
    return res.status(400).json({ message: 'Confirm physical office custody and provide a reason and storage location.' });
  }
  try {
    const itemId = await lifecycle.resolveItem('disposal_record', 'disposal_id', Number(req.params.disposalId));
    const result = await lifecycle.withItem(itemId, async (connection, item) => {
      if (item.item_type !== 'FOUND' || item.status !== 'DISPOSED') lifecycle.fail('Only a currently disposed item can be restored.');
      requireUnclaimed(await lifecycle.claims(connection, itemId));
      const record = requireCurrentDisposal(await lifecycle.disposals(connection, itemId), req.params.disposalId, 'COMPLETED');
      const retentionRows = await lifecycle.retentions(connection, itemId);
      if (lifecycle.openRetentions(retentionRows).length || !retentionRows.length ||
          retentionRows[retentionRows.length - 1].retention_status !== 'COMPLETED') {
        lifecycle.fail('Retention history is inconsistent; manual review is required.');
      }
      const days = await lifecycle.retentionDays(connection);
      const [updated] = await connection.query(`UPDATE disposal_record SET disposal_status = 'REVERSED',
        remarks = CONCAT_WS('\n', NULLIF(remarks,''), ?) WHERE disposal_id = ? AND disposal_status = 'COMPLETED'`,
      [`Reversal: ${reason}`, record.disposal_id]);
      lifecycle.changed(updated);
      const [itemResult] = await connection.query(`UPDATE item SET status = 'ACTIVE', custody_status = 'RECEIVED', storage_location = ?
        WHERE item_id = ? AND status = 'DISPOSED'`, [storage, itemId]);
      lifecycle.changed(itemResult);
      const [inserted] = await connection.query(`INSERT INTO retention_record
        (item_id,retention_start_date,retention_due_date,retention_status)
        VALUES (?,CURDATE(),DATE_ADD(CURDATE(),INTERVAL ? DAY),'ACTIVE')`, [itemId, days]);
      await lifecycle.expireOtps(connection, itemId);
      await lifecycle.audit(connection, req.user.user_id, itemId, 'DISPOSAL_REVERSED',
        `Disposal ${record.disposal_id} reversed: ${reason}. Physical custody confirmed; storage ${storage}. Original method/date preserved.`);
      await lifecycle.audit(connection, req.user.user_id, itemId, 'RETENTION_REOPENED',
        `New retention ${inserted.insertId} for ${days} days; prior cycles preserved.`);
      const [retention] = await connection.query(`SELECT retention_id,item_id,
        DATE_FORMAT(retention_start_date,'%Y-%m-%d') AS retention_start_date,
        DATE_FORMAT(retention_due_date,'%Y-%m-%d') AS retention_due_date,retention_status
        FROM retention_record WHERE retention_id = ?`, [inserted.insertId]);
      return { disposal: { disposal_id: record.disposal_id, item_id: itemId, disposal_status: 'REVERSED' },
        retention_period_days: days, retention: retention[0] };
    });
    return res.json({ success: true, message: 'Disposal reversed and a new retention period created', ...result });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to reverse disposal'); }
};
module.exports = { getDisposalRecords, createDisposalRecord, updateDisposalStatus, reverseDisposal };
