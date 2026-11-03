// In-process mocks only: no .env, database, API listener or model downloads.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const test = require('node:test');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zf2kAAAAASUVORK5CYII=', 'base64');
const realStorage = require('../services/image_storage_service');
const good = () => ({ success: true, status: 'compared', category_compatible: true,
  model_conflict: false, overall_similarity_score: 0.9,
  component_scores: { image: 0.9, text: 0.8, model: null, colour: 1 }, evidence_components_available: 3 });
function fixture(options = {}) {
  const state = { items: [
    { item_id: 1, reporter_id: 7, item_type: 'LOST', category_id: 1, category_name: 'Bottle', item_name: 'Synthetic bottle',
      description: 'Synthetic blue bottle', colour: 'blue', model_info: null, status: 'ACTIVE', publication_status: 'PUBLISHED', value_tier: 'MEDIUM', image_path: 'uploads/lost.png' },
    { item_id: 2, reporter_id: 8, item_type: 'FOUND', category_id: 1, category_name: 'Bottle', item_name: 'Synthetic found bottle',
      description: 'Synthetic blue bottle', colour: 'blue', model_info: null, status: 'ACTIVE', publication_status: 'PUBLISHED', value_tier: 'MEDIUM', image_path: 'uploads/found.png' }
  ], images: [], matches: [], notifications: [], disposals: [], calls: [], ai: [], triggers: [], commits: 0, rollbacks: 0, files: new Map() };
  let snapshot;
  const pool = {
    async query(sql, p = []) {
      const q = sql.replace(/\s+/g, ' ').trim(); state.calls.push({ sql: q, parameters: p });
      if (options.failImageInsert && q.startsWith('INSERT INTO item_image')) throw new Error('Synthetic image reference failure');
      if (q.includes('FROM item_category') && !q.includes('JOIN')) return [[{ category_id: 1, category_name: 'Bottle', default_value_tier: options.tier || 'MEDIUM' }]];
      if (q.includes('FROM item i')) {
        if (q.includes('WHERE i.item_id IN')) return [structuredClone(state.items.filter(i => p.includes(i.item_id)))];
        if (q.includes('WHERE i.item_type=?')) return [structuredClone(state.items.filter(i => i.item_type === p[0] && i.category_id === p[1] && i.item_id !== p[2] && i.reporter_id !== p[3] && i.publication_status === 'PUBLISHED' && ['ACTIVE','MATCHED','CLAIM_PENDING'].includes(i.status)))];
        if (q.includes('WHERE i.item_id')) return [structuredClone(state.items.filter(i => i.item_id === p[0]))];
        return [structuredClone(state.items)];
      }
      if (q.includes('FROM item WHERE item_id')) return [structuredClone(state.items.filter(i => i.item_id === p[0]))];
      if (q.startsWith('INSERT INTO item (')) {
        const row = { item_id: state.items.length + 1, reporter_id: p[0], category_id: p[1], item_name: p[2], model_info: p[3], colour: p[4], description: p[5],
          item_type: p[6], value_tier: p[7], status: 'ACTIVE', publication_status: p[8], custody_status: p[9], location: p[10], event_date: p[11] };
        state.items.push(row); return [{ insertId: row.item_id }];
      }
      if (q.startsWith('INSERT INTO item_security_question')) return [{ insertId: 1 }];
      if (q.startsWith('SELECT image_path FROM item_image WHERE item_id=?')) return [[{ image_path: state.items.find(i => i.item_id === p[0])?.image_path }]];
      if (q.includes('FROM item_image')) {
        if (q.includes('WHERE image_id')) return [state.images.filter(i => i.image_id === p[0] && i.item_id === p[1])];
        if (q.includes('WHERE item_id IN')) return [state.images.filter(i => p[0].includes(i.item_id))];
        return [state.images.filter(i => i.item_id === p[0] && (p.length < 2 || i.image_path === p[1]))];
      }
      if (q.startsWith('INSERT INTO item_image')) {
        const image = { image_id: state.images.length + 1, item_id: p[0], image_path: p[1], image_role: p[2] };
        state.images.push(image); return [{ insertId: image.image_id }];
      }
      if (q.startsWith('UPDATE item SET publication_status')) { state.items.find(i => i.item_id === p[0]).publication_status = 'PENDING_REVIEW'; return [{ affectedRows: 1 }]; }
      if (q.includes('FROM disposal_record')) return [state.disposals];
      if (q.startsWith('SELECT match_id,match_status')) return [state.matches.filter(m => m.lost_item_id === p[0] && m.found_item_id === p[1])];
      if (q.startsWith('INSERT INTO match_result')) {
        assert.equal(state.matches.length, 0, 'same pair must not be inserted twice');
        state.matches.push({ match_id: 9, lost_item_id: p[0], found_item_id: p[1], image_similarity: p[2], text_similarity: p[3], overall_similarity: p[7], match_status: 'SUGGESTED' });
        return [{ insertId: 9, affectedRows: 1 }];
      }
      if (q.startsWith('UPDATE match_result')) { state.matches[0].overall_similarity = p[5]; return [{ affectedRows: 1 }]; }
      if (q.startsWith('INSERT INTO notification')) {
        if (options.failNotification) throw new Error('Synthetic notification failure');
        state.notifications.push({ user_id: p[0], item_id: p[1], type: 'MATCH_SUGGESTED' }); return [{ insertId: 1 }];
      }
      throw new Error(`Unexpected mocked SQL: ${q}`);
    },
    async getConnection() { return this; },
    async beginTransaction() { snapshot = structuredClone({ items: state.items, images: state.images, matches: state.matches, notifications: state.notifications }); },
    async commit() { state.commits++; snapshot = null; },
    async rollback() { state.rollbacks++; if (snapshot) Object.assign(state, snapshot); snapshot = null; }, release() {}
  };
  const storage = { ...realStorage,
    async storeImage(reference, buffer) { const created = !state.files.has(reference); state.files.set(reference, buffer); return created; },
    async removeImage(reference) { state.files.delete(reference); },
    async readImage(reference) { if (options.missingImage) throw new Error('Synthetic missing image'); return { buffer: png, mime: 'image/png', name: reference.split('/').at(-1) }; }
  };
  const cache = new Map();
  function load(file) {
    if (cache.has(file)) return cache.get(file);
    const filename = path.resolve(__dirname, '..', file), local = createRequire(filename), module = { exports: {} };
    vm.compileFunction(fs.readFileSync(filename, 'utf8'), ['module','require','console','process','fetch','setTimeout','clearTimeout','setImmediate'], { filename })(module,
      name => {
        if (name === '../config/db') return pool;
        if (name.endsWith('image_storage_service')) return storage;
        if (name.endsWith('automatic_matching_service')) return { triggerMatching(id) { state.triggers.push(id); }, markImagePending() {}, markImageReady() {} };
        if (name.endsWith('audit_log_service')) return { async createAuditLog() {} };
        if (name === 'axios') return { async post(url, form) { state.ai.push({ url, form }); return { data: options.analysisResult ?? { success: true, suggested_category: 'Bottle', relative_score_percent: 80, generated_description: 'Synthetic bottle' } }; } };
        return local(name);
      }, { error() {}, warn() {}, log() {} }, { env: {} },
      async (url, request) => {
        state.ai.push({ url, form: request.body });
        if (options.onAi) await options.onAi(state, request.body);
        if (options.aiFailure) throw new Error('Synthetic AI outage');
        return { ok: true, async json() { return options.result ?? good(); } };
      }, setTimeout, clearTimeout, callback => callback());
    cache.set(file, module.exports); return module.exports;
  }
  return { state, load };
}
async function call(f, handler, { userId = 7, role = 'USER', id = '1', imageId = '1', file, body = {} } = {}) {
  const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(value) { this.body = value; return this; }, set(value) { this.headers = value; }, send(value) { this.body = value; return this; } };
  await f.load('controllers/item_controller.js')[handler]({ user: { user_id: userId, role }, params: { id, imageId }, file, body }, res);
  return res;
}
const upload = (f, extra = {}) => call(f, 'uploadItemImage', { file: { buffer: png, mimetype: 'image/png', originalname: 'malicious.html' }, ...extra });
const payload = type => ({ item_type: type, item_name: 'Synthetic report', category_id: 1,
  security_questions: [{ question: 'What is hidden inside?', answer: 'Synthetic contents' }, { question: 'What is the hidden mark?', answer: 'Synthetic mark' }] });
for (const type of ['LOST', 'FOUND']) test(`${type} report with deferred matching does not run AI before upload`, async () => {
  const f = fixture(); const response = await call(f, 'createItem', { body: { ...payload(type), defer_matching: true } });
  assert.equal(response.statusCode, 201); assert.equal(f.state.triggers.length, 0); assert.equal(f.state.ai.length, 0);
});
test('upload uses canonical content reference, commits association, then triggers matching', async () => {
  const f = fixture(); const response = await upload(f); assert.equal(response.statusCode, 201);
  assert.match(response.body.image.image_path, /^uploads\/1-[a-f0-9]{64}\.png$/);
  assert.equal(response.body.image.image_url, '/api/items/1/images/1'); assert.equal(f.state.images[0].image_role, 'PRIMARY'); assert.deepEqual(f.state.triggers, [1]);
});
test('repeated identical upload reuses image record, even if response was lost', async () => { const f = fixture(); const first = await upload(f), second = await upload(f); assert.equal(second.statusCode, 201); assert.equal(first.body.image.image_id, second.body.image.image_id); assert.equal(f.state.images.length, 1); assert.equal(f.state.files.size, 1); });
test('unauthorized upload creates no disk file or image reference', async () => { const f = fixture(); assert.equal((await upload(f, { userId: 99 })).statusCode, 403); assert.equal(f.state.files.size, 0); assert.equal(f.state.images.length, 0); });
for (const status of ['CLAIMED','DISPOSED','EXPIRED']) test(`upload cannot change ${status} report`, async () => { const f = fixture(); f.state.items[0].status = status; assert.equal((await upload(f)).statusCode, 409); assert.equal(f.state.files.size, 0); });
test('invalid disguised file is rejected before any persistence', async () => { const f = fixture(); assert.equal((await upload(f, { file: { buffer: Buffer.from('<html>'), mimetype: 'image/png' } })).statusCode, 400); assert.equal(f.state.calls.length, 0); });
test('failed image association rolls back and removes only an unreferenced file', async () => { const f = fixture({ failImageInsert: true }); assert.equal((await upload(f)).statusCode, 500); assert.equal(f.state.images.length, 0); assert.equal(f.state.files.size, 0); assert.equal(f.state.triggers.length, 0); });
test('HIGH new image requires re-review, repeated same evidence does not reset review', async () => {
  const f = fixture(); f.state.items[0].value_tier = 'HIGH'; assert.equal((await upload(f)).body.publication_status, 'PENDING_REVIEW');
  f.state.items[0].publication_status = 'PUBLISHED'; assert.equal((await upload(f)).body.publication_status, 'PUBLISHED'); assert.equal(f.state.images.length, 1);
});
test('only an owner/admin can view unpublished images; HIGH found images remain private', async () => {
  const f = fixture(); await upload(f); f.state.items[0].publication_status = 'PENDING_REVIEW';
  assert.equal((await call(f, 'getItemImage', { userId: 99 })).statusCode, 404);
  assert.equal((await call(f, 'getItemImage')).statusCode, 200);
  f.state.items[0].item_type = 'FOUND'; f.state.items[0].value_tier = 'HIGH'; f.state.items[0].publication_status = 'PUBLISHED';
  assert.equal((await call(f, 'getItemImage', { userId: 99 })).statusCode, 404);
  const response = await call(f, 'getItemImage', { userId: 99, role: 'ADMIN' }); assert.equal(response.statusCode, 200); assert.equal(response.headers['Cache-Control'], 'private, no-store');
});
test('image ID must belong to the requested item', async () => { const f = fixture(); await upload(f); assert.equal((await call(f, 'getItemImage', { id: '2' })).statusCode, 404); });
test('list API supplies authorized URLs and hides HIGH found evidence', async () => {
  const f = fixture(); await upload(f); f.state.items[1].value_tier = 'HIGH';
  const response = await call(f, 'getAllItems'); assert.equal(response.statusCode, 200); assert.equal(response.body.items[0].image_url, '/api/items/1/images/1');
  assert.deepEqual(response.body.items[1].images, []); assert.equal(response.body.items[1].description, null);
});
for (const type of ['LOST','FOUND']) test(`matching ${type} source uses persisted opposite images and preserves component scores`, async () => {
  const f = fixture(); const result = await f.load('services/automatic_matching_service.js').runMatchingForItem(type === 'LOST' ? 1 : 2);
  assert.equal(result.saved, 1); assert.equal(f.state.matches[0].overall_similarity, 0.9); assert.equal(f.state.matches[0].image_similarity, 0.9);
  assert.equal(f.state.ai[0].form.get('lost_image').type, 'image/png'); assert.equal(f.state.ai[0].form.get('found_image').type, 'image/png');
  assert.equal(f.state.notifications[0].user_id, 7);
});
test('repeated matching does not duplicate pairs or notifications', async () => {
  const f = fixture(), service = f.load('services/automatic_matching_service.js'); await service.runMatchingForItem(1); await service.runMatchingForItem(1);
  assert.equal(f.state.matches.length, 1); assert.equal(f.state.notifications.length, 1);
});
test('new upload trigger during active matching schedules a fresh pass', async () => {
  let release, started; const entered = new Promise(resolve => { started = resolve; }); const gate = new Promise(resolve => { release = resolve; }); let first = true;
  const f = fixture({ onAi: async () => { if (first) { first = false; started(); await gate; } } });
  const service = f.load('services/automatic_matching_service.js'); const a = service.runMatchingForItem(1); await entered;
  const b = service.runMatchingForItem(1); release(); await Promise.all([a,b]); assert.equal(f.state.ai.length, 2); assert.equal(f.state.matches.length, 1); assert.equal(f.state.notifications.length, 1);
});
for (const options of [{ aiFailure: true }, { missingImage: true }, { result: { ...good(), overall_similarity_score: 'not-a-number' } }]) test(`unavailable/malformed AI never saves misleading match ${JSON.stringify(options)}`, async () => { const f = fixture(options); const result = await f.load('services/automatic_matching_service.js').runMatchingForItem(1); assert.equal(result.errors, 1); assert.equal(f.state.matches.length, 0); assert.equal(f.state.notifications.length, 0); });
for (const property of ['status','publication_status','image_path']) test(`changed ${property} while AI is running cannot save stale evidence`, async () => {
  const f = fixture({ onAi(state) { state.items[1][property] = { status: 'DISPOSED', publication_status: 'PENDING_REVIEW', image_path: 'uploads/new.png' }[property]; } });
  const result = await f.load('services/automatic_matching_service.js').runMatchingForItem(1); assert.equal(result.saved, 0); assert.equal(f.state.notifications.length, 0);
});
test('completed disposal on legacy ACTIVE item blocks matching without repairing records', async () => { const f = fixture(); f.state.disposals.push({ disposal_id: 1 }); await f.load('services/automatic_matching_service.js').runMatchingForItem(1); assert.equal(f.state.matches.length, 0); assert.equal(f.state.items[1].status, 'ACTIVE'); });
test('notification failure rolls back match creation so retry can notify once', async () => { const options = { failNotification: true }, f = fixture(options), service = f.load('services/automatic_matching_service.js'); assert.equal((await service.runMatchingForItem(1)).errors, 1); assert.equal(f.state.matches.length, 0); options.failNotification = false; await service.runMatchingForItem(1); assert.equal(f.state.matches.length, 1); assert.equal(f.state.notifications.length, 1); });
for (const status of ['REJECTED','CONFIRMED']) test(`matching preserves ${status} decision`, async () => { const f = fixture(); f.state.matches.push({ match_id: 9, lost_item_id: 1, found_item_id: 2, match_status: status, overall_similarity: 0.8 }); await f.load('services/automatic_matching_service.js').runMatchingForItem(1); assert.equal(f.state.matches[0].match_status, status); assert.equal(f.state.matches[0].overall_similarity, 0.8); assert.equal(f.state.notifications.length, 0); });
test('recomputation retains historical suggestion but refreshes its below-threshold score', async () => { const options = {}, f = fixture(options), service = f.load('services/automatic_matching_service.js'); await service.runMatchingForItem(1); options.result = { ...good(), overall_similarity_score: 0.4 }; await service.runMatchingForItem(1); assert.equal(f.state.matches[0].overall_similarity, 0.4); assert.equal(f.state.matches.length, 1); assert.equal(f.state.notifications.length, 1); });
for (const [name, change] of [['same reporter', item => { item.reporter_id = 7; }], ['same type', item => { item.item_type = 'LOST'; }], ['different category', item => { item.category_id = 2; }], ['unpublished', item => { item.publication_status = 'PENDING_REVIEW'; }]]) test(`candidate query excludes ${name}`, async () => { const f = fixture(); change(f.state.items[1]); await f.load('services/automatic_matching_service.js').runMatchingForItem(1); assert.equal(f.state.ai.length, 0); });
test('AI preview forwards the selected image bytes and validates response shape', async () => {
  for (const malformed of [false, true]) {
    const f = fixture(malformed ? { analysisResult: { success: true } } : {}); const res = { statusCode: 200, status(code) { this.statusCode = code; return this; }, json(body) { this.body = body; return this; } };
    await f.load('controllers/ai_controller.js').analyzeImage({ file: { buffer: png, mimetype: 'image/png', originalname: 'selected.png' } }, res);
    assert.equal(res.statusCode, malformed ? 502 : 200); assert.equal(f.state.ai.length, 1);
  }
});
test('storage rejects traversal, symlink escapes and oversized files without serving sensitive bytes', async () => {
  let fileRead = false;
  const filename = path.resolve(__dirname, '../services/image_storage_service.js'), module = { exports: {} };
  vm.compileFunction(fs.readFileSync(filename, 'utf8'), ['module','require','process','__dirname'], { filename })(module,
    name => name === 'node:fs/promises' ? {
      async realpath(file) { return file.includes('secret') ? path.resolve('outside/secret.png') : file; },
      async stat() { return { isFile: () => true, size: 6 * 1024 * 1024 }; },
      async readFile() { fileRead = true; return png; }
    } : require(name), { env: {} }, path.dirname(filename));
  await assert.rejects(module.exports.readImage('uploads/../../.env'));
  await assert.rejects(module.exports.readImage('uploads/secret.png'));
  await assert.rejects(module.exports.readImage('uploads/large.png')); assert.equal(fileRead, false);
});

test('a single available image is forwarded for BLIP text evidence without inventing image similarity', async () => {
  const f = fixture({ result: { ...good(), component_scores: { image: null, text: 0.9, model: null, colour: 1 } } });
  f.state.items[1].image_path = null;
  await f.load('services/automatic_matching_service.js').runMatchingForItem(1);
  assert.ok(f.state.ai[0].form.get('lost_image'));
  assert.equal(f.state.ai[0].form.get('found_image'), null);
  assert.equal(f.state.matches[0].image_similarity, null);
});

for (const [code, status] of [['LIMIT_FILE_SIZE', 413], ['LIMIT_UNEXPECTED_FILE', 400]]) {
  test(`upload route returns JSON ${status} for ${code} before calling storage/controller`, async () => {
    const routes = []; let authorized = false;
    const router = { use(handler) { authorized = typeof handler === 'function'; },
      get(path, ...handlers) { routes.push({ method: 'GET', path, handlers }); },
      post(path, ...handlers) { routes.push({ method: 'POST', path, handlers }); }, patch() {} };
    const filename = path.resolve(__dirname, '../routes/item_routes.js'), module = { exports: {} };
    vm.compileFunction(fs.readFileSync(filename, 'utf8'), ['module','require'], { filename })(module,
      name => {
        if (name === 'express') return { Router: () => router };
        if (name.endsWith('auth_middleware')) return () => {};
        if (name.endsWith('upload_middleware')) return { single: () => (req, res, callback) => callback({ code, message: 'Synthetic upload rejection' }) };
        if (name.includes('controller')) return new Proxy({}, { get: () => () => { throw new Error('Controller must not run after upload rejection'); } });
        throw new Error(`Unexpected route dependency: ${name}`);
      });
    const route = routes.find(r => r.method === 'POST' && r.path === '/:id/images');
    const response = { status(value) { this.statusCode = value; return this; }, json(value) { this.body = value; return this; } };
    route.handlers[0]({}, response, () => { throw new Error('Rejected upload must stop'); });
    assert.equal(response.statusCode, status); assert.equal(response.body.message, 'Synthetic upload rejection');
    assert.ok(authorized); assert.ok(routes.some(r => r.method === 'GET' && r.path === '/:id/images/:imageId'));
  });
}

test('a report waiting for its first upload is excluded as source and candidate until ready', async () => {
  const f = fixture(), service = f.load('services/automatic_matching_service.js');
  service.markImagePending(2);
  assert.equal((await service.runMatchingForItem(2)).skipped_reason, 'image_upload_pending');
  await service.runMatchingForItem(1); assert.equal(f.state.ai.length, 0); assert.equal(f.state.matches.length, 0);
  service.markImageReady(2); await service.runMatchingForItem(1);
  assert.equal(f.state.matches.length, 1); assert.equal(f.state.notifications.length, 1);
});
