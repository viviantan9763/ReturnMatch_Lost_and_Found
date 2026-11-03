// Synthetic transactional persistence only. No .env, server, or MySQL connection.
// The mutex models competing item actions; it does not prove InnoDB locking.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

function fixture(options = {}) {
  const state = {
    item: { item_id: 55, item_name: 'Synthetic item', item_type: 'FOUND', status: 'ACTIVE',
      publication_status: 'PUBLISHED', reporter_id: 9, value_tier: 'HIGH',
      custody_status: 'RECEIVED', storage_location: 'Synthetic shelf', ...options.item },
    claims: options.claims ?? [{ claim_id: 101, item_id: 55, claimant_id: 7, claim_status: 'APPROVED' }],
    otps: [{ otp_id: 1, claim_id: 101, otp_code: '123456', otp_status: 'ACTIVE', valid: true }],
    retentions: options.retentions ?? [{ retention_id: 1, item_id: 55, retention_status: 'ACTIVE', is_due: 1 }],
    disposals: options.disposals ?? [], audits: [], calls: [], commits: 0, rollbacks: 0, releases: 0
  };
  let queue = Promise.resolve();
  let failAudit = options.failAudit;
  const snapshot = () => structuredClone({ item: state.item, claims: state.claims, otps: state.otps,
    retentions: state.retentions, disposals: state.disposals, audits: state.audits });
  async function query(sql, p = [], connection) {
    const q = sql.replace(/\s+/g, ' ').trim();
    state.calls.push({ sql: q, parameters: p });
    if (options.failSql && q.includes(options.failSql)) throw Object.assign(new Error('Synthetic SQL failure'), { code: options.failCode });
    if (/^SELECT .* FROM item WHERE item_id = \? FOR UPDATE$/.test(q)) {
      const previous = queue;
      queue = new Promise(resolve => { connection.unlock = resolve; });
      await previous;
      connection.snapshot = snapshot();
      return [[{ ...state.item }]];
    }
    if (/^SELECT item_id FROM (claim|disposal_record)/.test(q)) {
      const rows = q.includes('FROM claim ') ? state.claims : state.disposals;
      return [rows.filter(row => Number(row.claim_id ?? row.disposal_id) === Number(p[0])).map(row => ({ item_id: row.item_id }))];
    }
    if (q.startsWith('SELECT retention_id FROM retention_record')) return [state.retentions.filter(r => ['ACTIVE', 'DUE'].includes(r.retention_status))];
    if (q.startsWith('SELECT disposal_id FROM disposal_record')) return [state.disposals.filter(d => ['PENDING', 'COMPLETED'].includes(d.disposal_status))];
    if (/^SELECT DISTINCT item_id FROM retention_record/.test(q)) return [state.retentions.some(r => r.retention_status === 'ACTIVE' && r.is_due) ? [{ item_id: 55 }] : []];
    if (q.startsWith('SELECT * FROM claim WHERE item_id')) return [state.claims.map(c => ({ ...c }))];
    if (q.startsWith('SELECT * FROM disposal_record WHERE item_id')) return [state.disposals.map(d => ({ ...d }))];
    if (q.startsWith('SELECT *, retention_due_date')) return [state.retentions.map(r => ({ ...r }))];
    if (q.includes('SELECT setting_value')) return [[{ setting_value: options.days ?? '30' }]];
    if (/^SELECT claimant_id,claim_status FROM claim/.test(q)) return [state.claims.filter(c => Number(c.claim_id) === Number(p[0]))];
    if (q.includes('FROM claim_otp') && q.startsWith('SELECT')) {
      if (q.includes('WHERE otp_code=?')) return [[]]; // synthetic generation collision probe
      return [state.otps.filter(o => o.otp_status === 'ACTIVE' && o.valid && Number(o.claim_id) === Number(p[0]) &&
        (p.length < 2 || o.otp_code === p[1]))];
    }
    if (/^UPDATE claim_otp SET otp_status = 'USED'/.test(q)) {
      const row = state.otps.find(o => o.otp_id === p[0] && o.otp_status === 'ACTIVE' && o.valid);
      if (row) { row.otp_status = 'USED'; row.used_at = 'synthetic now'; }
      return [{ affectedRows: row ? 1 : 0 }];
    }
    if (q.startsWith('UPDATE claim_otp')) {
      for (const row of state.otps) if (row.otp_status === 'ACTIVE') row.otp_status = 'EXPIRED';
      return [{ affectedRows: 1 }];
    }
    if (q.startsWith('INSERT INTO claim_otp')) {
      const row = { otp_id: state.otps.length + 1, claim_id: p[0], otp_code: p[1], otp_status: 'ACTIVE', valid: true };
      state.otps.push(row); return [{ insertId: row.otp_id }];
    }
    if (q.startsWith("UPDATE claim SET claim_status = 'COLLECTED'")) {
      const row = state.claims.find(c => c.claim_id === p[0] && c.claim_status === 'APPROVED');
      if (row) row.claim_status = 'COLLECTED';
      return [{ affectedRows: row ? 1 : 0 }];
    }
    if (q.startsWith("UPDATE item SET custody_status = 'RECEIVED'")) { state.item.custody_status = 'RECEIVED'; state.item.storage_location = p[0]; return [{ affectedRows: 1 }]; }
    if (q.startsWith('UPDATE item SET')) {
      if (options.zeroItemUpdate) return [{ affectedRows: 0 }];
      if (q.includes("status = 'CLAIMED'")) { state.item.status = 'CLAIMED'; state.item.custody_status = null; state.item.storage_location = null; }
      else if (q.includes("status = 'DISPOSED',")) { state.item.status = 'DISPOSED'; state.item.custody_status = null; state.item.storage_location = null; }
      else if (q.includes("status = 'EXPIRED' WHERE")) state.item.status = 'EXPIRED';
      else { state.item.status = 'ACTIVE'; if (q.includes("custody_status = 'RECEIVED'")) { state.item.custody_status = 'RECEIVED'; state.item.storage_location = p[0]; } }
      return [{ affectedRows: 1 }];
    }
    if (q.startsWith('UPDATE retention_record SET')) {
      const row = state.retentions.find(r => r.retention_id === p[0]);
      const due = q.includes("SET retention_status = 'DUE'");
      const valid = row && (due ? row.retention_status === 'ACTIVE' && row.is_due : ['ACTIVE', 'DUE'].includes(row.retention_status));
      if (valid) { row.retention_status = due ? 'DUE' : 'COMPLETED'; row.checked_at = 'synthetic now'; }
      return [{ affectedRows: valid ? 1 : 0 }];
    }
    if (q.startsWith('INSERT INTO disposal_record')) {
      const row = { disposal_id: state.disposals.length + 1, item_id: p[0], admin_id: p[1],
        disposal_status: 'PENDING', disposal_method: p[2], remarks: p[3], disposal_date: null };
      state.disposals.push(row); return [{ insertId: row.disposal_id }];
    }
    if (q.startsWith('UPDATE disposal_record SET')) {
      const reversal = q.includes("SET disposal_status = 'REVERSED'");
      const row = state.disposals.find(d => Number(d.disposal_id) === Number(reversal ? p[1] : p[4]));
      if (!row || row.disposal_status !== (reversal ? 'COMPLETED' : 'PENDING')) return [{ affectedRows: 0 }];
      row.disposal_status = reversal ? 'REVERSED' : p[0];
      if (!reversal) { row.disposal_method = p[1]; if (p[0] === 'COMPLETED') row.disposal_date = 'synthetic original date'; }
      row.remarks = [row.remarks, reversal ? p[0] : p[3]].filter(Boolean).join('\n');
      return [{ affectedRows: 1 }];
    }
    if (q.startsWith('INSERT INTO retention_record')) {
      const row = { retention_id: state.retentions.length + 1, item_id: p[0], retention_status: 'ACTIVE', is_due: 0,
        retention_start_date: '2026-11-04', retention_due_date: '2026-12-04' };
      state.retentions.push(row); return [{ insertId: row.retention_id }];
    }
    if (/^SELECT retention_id, ?item_id,/.test(q)) return [state.retentions.filter(r => r.retention_id === p[0])];
    if (q.startsWith('SELECT claim_id FROM claim')) {
      const own = q.includes('claimant_id');
      return [state.claims.filter(c => own ? c.claimant_id === p[1] && c.claim_status !== 'REJECTED' : ['APPROVED', 'COLLECTED'].includes(c.claim_status))];
    }
    if (q.startsWith('INSERT INTO claim ')) {
      state.claims.push({ claim_id: 101, item_id: p[0], claimant_id: p[1], claim_status: 'PENDING' });
      return [{ insertId: 101 }];
    }
    if (q.startsWith('SELECT r.retention_id')) return [state.retentions.map(r => ({ ...r, ...state.item,
      item_status: state.item.status, blocking_claim_count: state.claims.filter(c => c.claim_status !== 'REJECTED').length,
      live_disposal_count: state.disposals.filter(d => ['PENDING', 'COMPLETED'].includes(d.disposal_status)).length,
      open_retention_count: state.retentions.filter(r => ['ACTIVE', 'DUE'].includes(r.retention_status)).length,
      latest_retention_id: state.retentions.at(-1)?.retention_id }))];
    if (q.startsWith('SELECT d.*')) return [state.disposals.map(d => ({ ...d, item_type: state.item.item_type,
      item_status: state.item.status, custody_status: state.item.custody_status, storage_location: state.item.storage_location,
      blocking_claim_count: state.claims.filter(c => c.claim_status !== 'REJECTED').length,
      open_retention_count: state.retentions.filter(r => ['ACTIVE', 'DUE'].includes(r.retention_status)).length,
      due_retention_count: state.retentions.filter(r => r.retention_status === 'DUE' && r.is_due).length,
      latest_disposal_id: state.disposals.at(-1)?.disposal_id, latest_retention_status: state.retentions.at(-1)?.retention_status,
      live_disposal_count: state.disposals.filter(d => ['PENDING', 'COMPLETED'].includes(d.disposal_status)).length }))];
    if (q.startsWith('SELECT o.otp_id')) return [[]];
    throw new Error(`Unexpected mocked SQL: ${q}`);
  }
  const pool = {
    query: (sql, p) => query(sql, p),
    async getConnection() {
      if (options.failAcquire) throw new Error('Synthetic connection failure');
      return {
        query(sql, p) { return query(sql, p, this); },
        async beginTransaction() {},
        async commit() { state.commits++; this.snapshot = null; },
        async rollback() { state.rollbacks++; if (this.snapshot) { Object.assign(state, this.snapshot); this.snapshot = null; } },
        release() { state.releases++; this.unlock?.(); }
      };
    }
  };
  const cache = new Map();
  function load(file) {
    if (cache.has(file)) return cache.get(file);
    const filename = path.resolve(__dirname, '..', file);
    const module = { exports: {} };
    vm.compileFunction(fs.readFileSync(filename, 'utf8'), ['module', 'require', 'console'], { filename })(module,
      name => {
        if (name === '../config/db') return pool;
        if (name.endsWith('item_lifecycle_service')) return load('services/item_lifecycle_service.js');
        if (name.endsWith('audit_log_service')) return { async createAuditLog(entry) {
          assert.ok(entry.connection, 'audit must share the transaction');
          if (failAudit) throw new Error('Synthetic audit failure');
          const { connection, ...safe } = entry; state.audits.push(safe);
        } };
        if (name.endsWith('image_storage_service')) return require('../services/image_storage_service');
        if (name.endsWith('automatic_matching_service')) return { triggerMatching() {} };
        if (name.endsWith('otp_controller')) return {};
        if (name === 'crypto') return require('node:crypto');
        throw new Error(`Unexpected dependency: ${name}`);
      }, { error() {} });
    cache.set(file, module.exports); return module.exports;
  }
  return { state, load, allowAudit: () => { failAudit = false; } };
}
async function call(f, file, handler, { body = {}, params = {}, role = 'ADMIN', userId = 1 } = {}) {
  const response = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(value) { this.body = value; return this; } };
  await f.load(`controllers/${file}_controller.js`)[handler]({ user: { role, user_id: userId }, body, params }, response);
  return response;
}
const collect = (f, legacy = false, extra = {}) => call(f, legacy ? 'otp' : 'collection', legacy ? 'verifyOtp' : 'confirmCollection',
  { params: { claimId: '101' }, body: { claim_id: 101, otp_code: '123456' }, ...extra });
const create = f => call(f, 'disposal', 'createDisposalRecord', { params: { itemId: '55' } });
const update = (f, status = 'COMPLETED', extra = {}) => call(f, 'disposal', 'updateDisposalStatus',
  { params: { disposalId: '1' }, body: { status, disposal_method: 'RECYCLING', ...extra } });
const reverse = (f, extra = {}) => call(f, 'disposal', 'reverseDisposal', { params: { disposalId: '1' },
  body: { reason: 'Synthetic mistake', storage_location: 'New synthetic shelf', confirm_item_still_held: true, ...extra } });
function pending(options = {}) {
  return fixture({ claims: [], item: { status: 'EXPIRED' }, retentions: [{ retention_id: 1, item_id: 55, retention_status: 'DUE', is_due: 1 }],
    disposals: [{ disposal_id: 1, item_id: 55, admin_id: 99, disposal_status: 'PENDING', disposal_method: null, remarks: 'Original remark' }], ...options });
}
function completed(options = {}) {
  return fixture({ claims: [], item: { status: 'DISPOSED', custody_status: null, storage_location: null },
    retentions: [{ retention_id: 1, item_id: 55, retention_status: 'COMPLETED', is_due: 1 }],
    disposals: [{ disposal_id: 1, item_id: 55, admin_id: 99, disposal_status: 'COMPLETED', disposal_method: 'DONATION', disposal_date: 'Original date', remarks: 'Original remark' }], ...options });
}

for (const legacy of [false, true]) {
  const label = legacy ? 'legacy OTP' : 'collection';
  test(`${label}: atomic collection consumes OTP, closes ALL open retentions, clears custody, expires other OTPs and audits`, async () => {
    const f = fixture();
    f.state.retentions.push({ retention_id: 2, item_id: 55, retention_status: 'DUE', is_due: 1 });
    f.state.otps.push({ otp_id: 2, claim_id: 101, otp_code: '654321', otp_status: 'ACTIVE', valid: true });
    assert.equal((await collect(f, legacy)).statusCode, 200);
    assert.equal(f.state.item.status, 'CLAIMED');
    assert.equal(f.state.item.custody_status, null);
    assert.equal(f.state.item.storage_location, null);
    assert.equal(f.state.claims[0].claim_status, 'COLLECTED');
    assert.equal(f.state.otps[0].otp_status, 'USED');
    assert.equal(f.state.otps[1].otp_status, 'EXPIRED');
    assert.ok(f.state.retentions.every(r => r.retention_status === 'COMPLETED'));
    assert.equal(f.state.audits.filter(a => a.action_type === 'RETENTION_COMPLETED').length, 2);
    assert.match(f.state.audits.find(a => a.action_type === 'CLAIM_COLLECTED').action_details, /Synthetic shelf/);
    assert.equal(f.state.commits, 1);
    const locks = f.state.calls.filter(c => c.sql.includes('FOR UPDATE'));
    assert.match(locks[0].sql, /^SELECT \* FROM item/);
    assert.equal((await collect(f, legacy)).statusCode, 409);
    assert.equal(f.state.audits.filter(a => a.action_type === 'CLAIM_COLLECTED').length, 1);
  });
  for (const [name, options] of [
    ['not received', { item: { custody_status: 'NOT_RECEIVED' } }],
    ['missing storage', { item: { storage_location: '' } }],
    ['disposed', { item: { status: 'DISPOSED' } }],
    ['reserved', { item: { status: 'EXPIRED' } }],
    ['lost item', { item: { item_type: 'LOST' } }],
    ['pending claim', { claims: [{ claim_id: 101, item_id: 55, claim_status: 'PENDING' }] }],
    ['legacy completed disposal on active item', { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }] }],
    ['pending disposal', { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'PENDING' }] }]
  ]) test(`${label}: rejects ${name}`, async () => {
    const f = fixture(options); assert.equal((await collect(f, legacy)).statusCode, 409);
    assert.equal(f.state.otps[0].otp_status, 'ACTIVE'); assert.equal(f.state.commits, 0);
  });
  test(`${label}: expired/ambiguous OTP rejected`, async () => {
    const f = fixture(); f.state.otps[0].valid = false;
    assert.equal((await collect(f, legacy)).statusCode, 400);
    f.state.otps[0].valid = true; f.state.otps.push({ ...f.state.otps[0], otp_id: 2 });
    assert.equal((await collect(f, legacy)).statusCode, 400);
  });
  test(`${label}: audit failure rolls all state back and can safely retry`, async () => {
    const f = fixture({ failAudit: true }); assert.equal((await collect(f, legacy)).statusCode, 500);
    assert.equal(f.state.item.status, 'ACTIVE'); assert.equal(f.state.claims[0].claim_status, 'APPROVED');
    assert.equal(f.state.otps[0].otp_status, 'ACTIVE'); assert.equal(f.state.retentions[0].retention_status, 'ACTIVE');
    assert.equal(f.state.audits.length, 0); f.allowAudit(); assert.equal((await collect(f, legacy)).statusCode, 200);
  });
  test(`${label}: USER denied before persistence`, async () => {
    const f = fixture(); assert.equal((await collect(f, legacy, { role: 'USER' })).statusCode, 403); assert.equal(f.state.calls.length, 0);
  });
}
for (const status of ['PENDING', 'VERIFICATION_REQUIRED', 'APPROVED', 'COLLECTED']) {
  test(`disposal rejects ${status} ownership claim without mutating it`, async () => {
    const f = fixture({ claims: [{ claim_id: 101, item_id: 55, claim_status: status }] });
    assert.equal((await create(f)).statusCode, 409); assert.equal(f.state.claims[0].claim_status, status); assert.equal(f.state.disposals.length, 0);
  });
}
test('create promotes overdue retention, reserves item, expires OTPs; complete preserves creator and audits actual actor', async () => {
  const f = fixture({ claims: [{ claim_id: 101, item_id: 55, claim_status: 'REJECTED' }] });
  assert.equal((await create(f)).statusCode, 201); assert.equal(f.state.item.status, 'EXPIRED');
  assert.equal(f.state.retentions[0].retention_status, 'DUE'); assert.equal(f.state.otps[0].otp_status, 'EXPIRED');
  assert.equal((await create(f)).statusCode, 409);
  assert.equal((await call(f, 'claim', 'createClaim', { body: { item_id: 55 }, userId: 7 })).statusCode, 400);
  assert.equal((await update(f)).statusCode, 200); assert.equal(f.state.item.status, 'DISPOSED');
  assert.equal(f.state.item.storage_location, null); assert.equal(f.state.retentions[0].retention_status, 'COMPLETED');
  assert.ok(f.state.disposals[0].disposal_date);
  assert.equal((await update(f)).statusCode, 409);
  assert.equal((await update(f, 'CANCELLED')).statusCode, 409);
});
test('completion requires effective method; accepts stored method and retains original creator', async () => {
  const f = pending(); assert.equal((await update(f, 'COMPLETED', { disposal_method: null })).statusCode, 400);
  f.state.disposals[0].disposal_method = 'DONATION';
  assert.equal((await update(f, 'COMPLETED', { disposal_method: null })).statusCode, 200);
  assert.equal(f.state.disposals[0].admin_id, 99);
  assert.equal(f.state.audits.find(a => a.action_type === 'DISPOSAL_COMPLETED').admin_id, 1);
});
for (const [name, options] of [
  ['future retention', { retentions: [{ retention_id: 1, retention_status: 'DUE', is_due: 0 }] }],
  ['missing retention', { retentions: [] }],
  ['duplicate retention', { retentions: [{ retention_id: 1, retention_status: 'DUE', is_due: 1 }, { retention_id: 2, retention_status: 'ACTIVE', is_due: 1 }] }],
  ['not held', { item: { custody_status: 'NOT_RECEIVED' } }],
  ['collected item', { item: { status: 'CLAIMED' } }],
  ['legacy completed disposal', { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }] }]
]) test(`disposal creation rejects ${name}`, async () => { const f = fixture({ claims: [], ...options }); assert.equal((await create(f)).statusCode, 409); });
test('cancellation restores availability, retains DUE cycle and history, repeated cancellation fails', async () => {
  const f = pending(); assert.equal((await update(f, 'CANCELLED', { remarks: 'Synthetic cancellation' })).statusCode, 200);
  assert.equal(f.state.item.status, 'ACTIVE'); assert.equal(f.state.retentions.length, 1); assert.equal(f.state.retentions[0].retention_status, 'DUE');
  assert.match(f.state.disposals[0].remarks, /Original remark/); assert.match(f.state.disposals[0].remarks, /Synthetic cancellation/);
  assert.equal((await update(f, 'CANCELLED')).statusCode, 409);
});
for (const status of ['COMPLETED', 'CANCELLED']) {
  test(`stale ${status} cannot change a collected item`, async () => { const f = pending({ item: { status: 'CLAIMED' } }); assert.equal((await update(f, status)).statusCode, 409); assert.equal(f.state.item.status, 'CLAIMED'); });
  test(`${status} rechecks newly conflicting claim`, async () => { const f = pending({ claims: [{ claim_id: 101, item_id: 55, claim_status: 'PENDING' }] }); assert.equal((await update(f, status)).statusCode, 409); });
  test(`${status} audit failure rolls back disposal/item/retention`, async () => { const f = pending({ failAudit: true }); assert.equal((await update(f, status)).statusCode, 500); assert.equal(f.state.item.status, 'EXPIRED'); assert.equal(f.state.disposals[0].disposal_status, 'PENDING'); assert.equal(f.state.retentions[0].retention_status, 'DUE'); });
}
test('reversal preserves original disposal date/method/history and opens a NEW custody/retention cycle', async () => {
  const f = completed(); assert.equal((await reverse(f)).statusCode, 200);
  assert.equal(f.state.item.status, 'ACTIVE'); assert.equal(f.state.item.custody_status, 'RECEIVED');
  assert.equal(f.state.item.storage_location, 'New synthetic shelf'); assert.equal(f.state.item.publication_status, 'PUBLISHED');
  assert.equal(f.state.disposals[0].disposal_method, 'DONATION'); assert.equal(f.state.disposals[0].disposal_date, 'Original date');
  assert.match(f.state.disposals[0].remarks, /Original remark/); assert.equal(f.state.retentions.length, 2);
  assert.equal(f.state.retentions[0].retention_status, 'COMPLETED'); assert.equal(f.state.retentions[1].retention_status, 'ACTIVE');
  assert.deepEqual(f.state.audits.map(a => a.action_type), ['DISPOSAL_REVERSED', 'RETENTION_REOPENED']);
  assert.equal((await reverse(f)).statusCode, 409);
});
for (const extra of [{ reason: '' }, { storage_location: '' }, { confirm_item_still_held: false }]) {
  test(`reversal requires explicit confirmation/reason/storage ${JSON.stringify(extra)}`, async () => { const f = completed(); assert.equal((await reverse(f, extra)).statusCode, 400); assert.equal(f.state.calls.length, 0); });
}
for (const [name, options] of [
  ['historical ACTIVE/PUBLISHED inconsistency', { item: { status: 'ACTIVE' } }],
  ['collected claim', { claims: [{ claim_id: 101, item_id: 55, claim_status: 'COLLECTED' }] }],
  ['open retention', { retentions: [{ retention_id: 1, item_id: 55, retention_status: 'ACTIVE', is_due: 1 }] }],
  ['later disposal', { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }, { disposal_id: 2, item_id: 55, disposal_status: 'CANCELLED' }] }]
]) test(`reversal rejects ${name}`, async () => { const f = completed(options); const before = structuredClone(f.state.item); assert.equal((await reverse(f)).statusCode, 409); assert.deepEqual(f.state.item, before); });
test('reversal audit failure restores all history and custody', async () => { const f = completed({ failAudit: true }); assert.equal((await reverse(f)).statusCode, 500); assert.equal(f.state.disposals[0].disposal_status, 'COMPLETED'); assert.equal(f.state.item.status, 'DISPOSED'); assert.equal(f.state.retentions.length, 1); });
test('conditional item update failure rolls OTP/claim back', async () => { const f = fixture({ zeroItemUpdate: true }); assert.equal((await collect(f)).statusCode, 409); assert.equal(f.state.otps[0].otp_status, 'ACTIVE'); assert.equal(f.state.claims[0].claim_status, 'APPROVED'); });
test('deadlock rolls back and returns retryable conflict without leaking a connection', async () => { const f = fixture({ failSql: 'SELECT * FROM item', failCode: 'ER_LOCK_DEADLOCK' }); assert.equal((await collect(f)).statusCode, 409); assert.equal(f.state.releases, 1); });
test('competing collection endpoints serialize to one success in the mock', async () => { const f = fixture(); const responses = await Promise.all([collect(f), collect(f, true)]); assert.deepEqual(responses.map(r => r.statusCode).sort(), [200, 409]); assert.equal(f.state.commits, 1); });
test('competing disposal reservations serialize to one success in the mock', async () => { const f = fixture({ claims: [] }); const responses = await Promise.all([create(f), create(f)]); assert.deepEqual(responses.map(r => r.statusCode).sort(), [201, 409]); assert.equal(f.state.disposals.length, 1); });
test('claim creation vs disposal reservation serializes, with no contradictory result', async () => {
  for (const claimFirst of [true, false]) {
    const f = fixture({ claims: [] });
    const claim = () => call(f, 'claim', 'createClaim', { body: { item_id: 55 }, userId: 7 });
    const operations = claimFirst ? [claim(), create(f)] : [create(f), claim()];
    const responses = await Promise.all(operations);
    assert.equal(responses.filter(r => r.statusCode === 201).length, 1);
    assert.ok(!(f.state.claims.length && f.state.disposals.length));
  }
});
test('retention read promotes only a due current office-held cycle and returns eligibility', async () => {
  const f = fixture({ claims: [] }); const response = await call(f, 'retention', 'getRetentionRecords');
  assert.equal(response.statusCode, 200); assert.equal(response.body.newly_due_count, 1); assert.equal(response.body.records[0].can_create_disposal, true);
  assert.equal(f.state.audits[0].action_type, 'RETENTION_DUE');
  assert.equal((await call(f, 'retention', 'getRetentionRecords')).body.newly_due_count, 0);
});
for (const options of [{ item: { status: 'CLAIMED' } }, { item: { custody_status: null } },
  { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }] }]) {
  test(`retention read leaves incompatible legacy records unchanged ${JSON.stringify(options)}`, async () => { const f = fixture(options); const response = await call(f, 'retention', 'getRetentionRecords'); assert.equal(response.body.newly_due_count, 0); assert.equal(f.state.retentions[0].retention_status, 'ACTIVE'); assert.equal(response.body.records[0].can_create_disposal, false); });
}
test('historical completed disposal on ACTIVE item is visible but cannot be reversed', async () => { const f = completed({ item: { status: 'ACTIVE' } }); const response = await call(f, 'disposal', 'getDisposalRecords'); assert.equal(response.body.records[0].can_reverse, false); assert.ok(response.body.records[0].lifecycle_block_reason); });
for (const handler of ['generateOtp', 'getActiveOtp']) {
  test(`${handler} requires office custody and rejects completed disposal`, async () => {
    for (const options of [{ item: { custody_status: 'NOT_RECEIVED' } }, { disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }] }]) {
      const f = fixture(options); assert.equal((await call(f, 'otp', handler, { params: { claimId: '101' }, userId: 7 })).statusCode, 409);
    }
  });
}
test('OTP generation expires previous OTP; claimant can retrieve, another user cannot', async () => {
  const f = fixture(); const response = await call(f, 'otp', 'generateOtp', { params: { claimId: '101' } });
  assert.equal(response.statusCode, 201); assert.match(response.body.otp.otp_code, /^\d{6}$/); assert.equal(f.state.otps[0].otp_status, 'EXPIRED');
  assert.equal((await call(f, 'otp', 'getActiveOtp', { params: { claimId: '101' }, role: 'USER', userId: 7 })).statusCode, 200);
  assert.equal((await call(f, 'otp', 'getActiveOtp', { params: { claimId: '101' }, role: 'USER', userId: 8 })).statusCode, 403);
});

for (const status of ['EXPIRED', 'CLAIMED', 'DISPOSED']) {
  test(`office receipt rejects ${status} before custody/retention changes`, async () => {
    const f = fixture({ item: { status, custody_status: 'NOT_RECEIVED' }, retentions: [] });
    assert.equal((await call(f, 'item', 'confirmItemReceived', { params: { id: '55' }, body: { storage_location: 'Synthetic shelf' } })).statusCode, 409);
    assert.equal(f.state.retentions.length, 0); assert.equal(f.state.item.custody_status, 'NOT_RECEIVED');
  });
}
test('office receipt starts a new retention and logs both actions in one transaction', async () => {
  const f = fixture({ item: { custody_status: 'NOT_RECEIVED' }, retentions: [] });
  const response = await call(f, 'item', 'confirmItemReceived', { params: { id: '55' }, body: { storage_location: 'Synthetic received shelf' } });
  assert.equal(response.statusCode, 200); assert.equal(f.state.item.custody_status, 'RECEIVED'); assert.equal(f.state.retentions.length, 1);
  assert.deepEqual(f.state.audits.map(a => a.action_type), ['ITEM_RECEIVED', 'RETENTION_STARTED']);
  assert.equal(response.body.retention.retention_due_date, '2026-12-04');
});
test('office receipt rejects legacy completed disposal without repairing the item', async () => {
  const f = fixture({ item: { custody_status: 'NOT_RECEIVED' }, retentions: [], disposals: [{ disposal_id: 1, item_id: 55, disposal_status: 'COMPLETED' }] });
  assert.equal((await call(f, 'item', 'confirmItemReceived', { params: { id: '55' }, body: { storage_location: 'Synthetic shelf' } })).statusCode, 409);
  assert.equal(f.state.item.status, 'ACTIVE'); assert.equal(f.state.retentions.length, 0);
});
test('office receipt audit failure rolls custody and retention back', async () => {
  const f = fixture({ item: { custody_status: 'NOT_RECEIVED' }, retentions: [], failAudit: true });
  assert.equal((await call(f, 'item', 'confirmItemReceived', { params: { id: '55' }, body: { storage_location: 'Synthetic shelf' } })).statusCode, 500);
  assert.equal(f.state.item.custody_status, 'NOT_RECEIVED'); assert.equal(f.state.retentions.length, 0);
});
test('another successful historical claim prevents collection', async () => {
  const f = fixture(); f.state.claims.push({ claim_id: 102, item_id: 55, claim_status: 'COLLECTED' });
  assert.equal((await collect(f)).statusCode, 409); assert.equal(f.state.otps[0].otp_status, 'ACTIVE');
});
test('two competing completions and cancellation/completion cannot both succeed in the mock', async () => {
  for (const second of ['COMPLETED', 'CANCELLED']) {
    const f = pending(); const responses = await Promise.all([update(f), update(f, second)]);
    assert.deepEqual(responses.map(r => r.statusCode).sort(), [200, 409]);
    assert.equal(f.state.audits.filter(a => a.action_type === 'DISPOSAL_COMPLETED').length, 1);
  }
});
test('two competing reversals produce one new retention cycle in the mock', async () => {
  const f = completed(); const responses = await Promise.all([reverse(f), reverse(f)]);
  assert.deepEqual(responses.map(r => r.statusCode).sort(), [200, 409]); assert.equal(f.state.retentions.length, 2);
});

test('valid completed disposal exposes restore eligibility', async () => {
  const f = completed(); const response = await call(f, 'disposal', 'getDisposalRecords');
  assert.equal(response.body.records[0].can_reverse, true);
});

test('connection acquisition failure returns a controlled error without any mutation', async () => {
  const f = fixture({ failAcquire: true }); assert.equal((await collect(f)).statusCode, 500);
  assert.equal(f.state.otps[0].otp_status, 'ACTIVE'); assert.equal(f.state.commits, 0);
});
test('disposal creation audit failure rolls back promotion, reservation, OTP expiry and new record', async () => {
  const f = fixture({ claims: [], failAudit: true }); assert.equal((await create(f)).statusCode, 500);
  assert.equal(f.state.item.status, 'ACTIVE'); assert.equal(f.state.retentions[0].retention_status, 'ACTIVE');
  assert.equal(f.state.disposals.length, 0); assert.equal(f.state.otps[0].otp_status, 'ACTIVE'); assert.equal(f.state.audits.length, 0);
});
for (const [handler, params, body] of [
  ['createDisposalRecord', { itemId: '55' }, {}],
  ['updateDisposalStatus', { disposalId: '1' }, { status: 'COMPLETED' }],
  ['reverseDisposal', { disposalId: '1' }, { reason: 'Synthetic', storage_location: 'Shelf', confirm_item_still_held: true }]
]) test(`USER cannot invoke ${handler}`, async () => {
  const f = fixture(); assert.equal((await call(f, 'disposal', handler, { role: 'USER', params, body })).statusCode, 403);
  assert.equal(f.state.calls.length, 0);
});
