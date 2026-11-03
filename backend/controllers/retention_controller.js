const pool = require('../config/db');
const lifecycle = require('../services/item_lifecycle_service');
const getRetentionRecords = async (req, res) => {
  if (!req.user || !['ADMIN', 'SUPER_ADMIN'].includes(req.user.role)) {
    return res.status(403).json({ message: 'Admin access required' });
  }
  try {
    // The read finds candidates only. Lock item first and re-read current rows;
    // never blanket-update or silently repair terminal historical records.
    const [candidates] = await pool.query(`SELECT DISTINCT item_id FROM retention_record
      WHERE retention_status = 'ACTIVE' AND retention_due_date <= CURDATE() ORDER BY item_id`);
    let newlyDue = 0;
    for (const candidate of candidates) {
      newlyDue += await lifecycle.withItem(candidate.item_id, async (connection, item) => {
        if (item.item_type !== 'FOUND' || !lifecycle.available(item) || !lifecycle.inCustody(item)) return 0;
        if (lifecycle.blockingDisposals(await lifecycle.disposals(connection, item.item_id)).length) return 0;
        const history = await lifecycle.retentions(connection, item.item_id);
        const open = lifecycle.openRetentions(history);
        if (open.length !== 1 || open[0].retention_id !== history[history.length - 1]?.retention_id || open[0].retention_status !== 'ACTIVE' || !Number(open[0].is_due)) return 0;
        return Number(await lifecycle.markDue(connection, item, open[0], req.user.user_id));
      });
    }
    const [records] = await pool.query(`SELECT r.retention_id,r.item_id,
      DATE_FORMAT(r.retention_start_date,'%Y-%m-%d') AS retention_start_date,
      DATE_FORMAT(r.retention_due_date,'%Y-%m-%d') AS retention_due_date,
      r.retention_status,r.checked_at,i.item_name,i.item_type,i.value_tier,i.status AS item_status,
      i.custody_status,i.location,i.storage_location,
      (r.retention_due_date<=CURDATE()) AS is_due,
      (SELECT COUNT(*) FROM claim c WHERE c.item_id=r.item_id AND c.claim_status <> 'REJECTED') AS blocking_claim_count,
      (SELECT COUNT(*) FROM disposal_record d WHERE d.item_id=r.item_id AND d.disposal_status IN ('PENDING','COMPLETED')) AS live_disposal_count,
      (SELECT COUNT(*) FROM retention_record x WHERE x.item_id=r.item_id AND x.retention_status IN ('ACTIVE','DUE')) AS open_retention_count,
      (SELECT MAX(x.retention_id) FROM retention_record x WHERE x.item_id=r.item_id) AS latest_retention_id
      FROM retention_record r JOIN item i ON i.item_id=r.item_id
      ORDER BY FIELD(r.retention_status,'DUE','ACTIVE','COMPLETED'),r.retention_due_date`);
    for (const row of records) {
      row.can_create_disposal = row.retention_status === 'DUE' && Number(row.is_due) === 1 &&
        row.item_type === 'FOUND' && lifecycle.available({ status: row.item_status }) && lifecycle.inCustody(row) &&
        !Number(row.blocking_claim_count) && !Number(row.live_disposal_count) && Number(row.open_retention_count) === 1 &&
        Number(row.latest_retention_id) === Number(row.retention_id);
      row.disposal_block_reason = row.can_create_disposal ? null :
        'Disposal requires a due retention cycle, office custody, and no unresolved or successful claim or disposal.';
    }
    return res.json({ success: true, count: records.length, newly_due_count: newlyDue, records });
  } catch (error) { return lifecycle.respondError(res, error, 'Failed to load retention records'); }
};
module.exports = { getRetentionRecords };
