// In-process route/controller tests. Database and password hashing are mocked;
// no application server, .env file, or database connection is used.
const assert = require('node:assert/strict');
const { randomBytes } = require('node:crypto');
const fs = require('node:fs');
const { createRequire } = require('node:module');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const jwt = require('jsonwebtoken');

const secret = randomBytes(32).toString('hex');
const validBody = {
  name: 'Synthetic Administrator',
  email: 'synthetic-admin@example.invalid',
  password: 'A distinct test passphrase'
};

function loadModule(relativePath, overrides = {}) {
  const filename = path.resolve(__dirname, '..', relativePath);
  const localRequire = createRequire(filename);
  const module = { exports: {} };
  const evaluate = vm.compileFunction(fs.readFileSync(filename, 'utf8'), [
    'module', 'exports', 'require', 'process', 'console', 'Buffer',
    '__dirname', '__filename'
  ], { filename });
  evaluate(module, module.exports,
    (name) => Object.hasOwn(overrides, name) ? overrides[name] : localRequire(name),
    { env: { JWT_SECRET: secret } },
    { error() {}, warn() {}, log() {} },
    Buffer, path.dirname(filename), filename);
  return module.exports;
}

function fixture({ duplicate = false } = {}) {
  const queries = [];
  const hashes = [];
  const pool = {
    async query(sql, parameters) {
      queries.push({ sql, parameters: Array.from(parameters || []) });
      if (/SELECT user_id/.test(sql)) {
        return [duplicate ? [{ user_id: 7 }] : []];
      }
      if (/INSERT INTO user/.test(sql)) return [{ insertId: 42 }];
      throw new Error('Unexpected database operation in test');
    }
  };
  const controller = loadModule('controllers/admin_controller.js', {
    '../config/db': pool,
    bcrypt: {
      async hash(password, rounds) {
        hashes.push({ password, rounds });
        return 'mock-bcrypt-hash';
      }
    }
  });
  const guard = loadModule('middleware/super_admin_middleware.js');
  const authenticate = loadModule('middleware/auth_middleware.js');
  const router = loadModule('routes/admin_routes.js', {
    '../middleware/auth_middleware': authenticate,
    '../middleware/super_admin_middleware': guard,
    '../controllers/admin_controller': controller
  });
  return { queries, hashes, controller, router };
}

function tokenFor(role, options = {}) {
  const payload = { user_id: 1 };
  if (role !== undefined) payload.role = role;
  return jwt.sign(payload, options.secret || secret, {
    expiresIn: options.expired ? -1 : '5m'
  });
}

function routeRequest(router, { token, body = validBody } = {}) {
  return new Promise((resolve, reject) => {
    const req = {
      method: 'POST', url: '/create-admin', originalUrl: '/create-admin',
      baseUrl: '', headers: token ? { authorization: `Bearer ${token}` } : {},
      body
    };
    const res = {
      statusCode: 200,
      status(code) { this.statusCode = code; return this; },
      json(value) { resolve({ status: this.statusCode, body: value }); return this; }
    };
    router.handle(req, res, (error) => reject(error || new Error('Route did not respond')));
  });
}

function response() {
  return {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; }
  };
}

test('missing authentication is rejected before database or hashing', async () => {
  const f = fixture();
  const result = await routeRequest(f.router);
  assert.equal(result.status, 401);
  assert.equal(f.queries.length, 0);
  assert.equal(f.hashes.length, 0);
});

for (const [label, token] of [
  ['invalid', 'invalid-token'],
  ['expired', tokenFor('SUPER_ADMIN', { expired: true })],
  ['wrong signature', tokenFor('SUPER_ADMIN', { secret: 'untrusted-test-key' })]
]) {
  test(`${label} token cannot create an administrator`, async () => {
    const f = fixture();
    assert.equal((await routeRequest(f.router, { token })).status, 403);
    assert.equal(f.queries.length, 0);
    assert.equal(f.hashes.length, 0);
  });
}

for (const role of ['USER', 'STUDENT', 'ADMIN', 'UNKNOWN', 'super_admin', undefined]) {
  test(`${role ?? 'missing role'} is denied, including a forged body role`, async () => {
    const f = fixture();
    const result = await routeRequest(f.router, {
      token: tokenFor(role), body: { ...validBody, role: 'SUPER_ADMIN' }
    });
    assert.equal(result.status, 403);
    assert.equal(f.queries.length, 0);
    assert.equal(f.hashes.length, 0);
  });
}

for (const user of [undefined, { role: 'USER' }, { role: 'STUDENT' }, { role: 'ADMIN' }]) {
  test(`controller independently denies ${user?.role ?? 'missing user'}`, async () => {
    const f = fixture();
    const res = response();
    await f.controller.createAdmin({ user, body: validBody }, res);
    assert.equal(res.statusCode, 403);
    assert.equal(f.queries.length, 0);
    assert.equal(f.hashes.length, 0);
  });
}

test('SUPER_ADMIN creates only ADMIN and preserves password whitespace', async () => {
  const f = fixture();
  const password = '  A distinct test passphrase  ';
  const result = await routeRequest(f.router, {
    token: tokenFor('SUPER_ADMIN'),
    body: { ...validBody, password, role: 'SUPER_ADMIN' }
  });
  assert.equal(result.status, 201);
  assert.equal(result.body.admin.role, 'ADMIN');
  assert.equal(result.body.admin.user_id, 42);
  assert.equal(f.hashes.length, 1);
  assert.equal(f.hashes[0].password, password);
  assert.equal(f.hashes[0].rounds, 10);
  assert.equal(f.queries.length, 2);
  assert.match(f.queries[1].sql, /VALUES\s*\(\?,\s*\?,\s*\?,\s*'ADMIN',\s*\?\)/);
  assert.equal(f.queries[1].parameters[2], 'mock-bcrypt-hash');
  assert.ok(!f.queries[1].parameters.includes('SUPER_ADMIN'));
});

for (const [label, password] of [
  ['short password', 'short'],
  ['common password', 'password1234'],
  ['over 72 UTF-8 bytes', '\u{1F510}'.repeat(19)],
  ['non-text password', 123456789012]
]) {
  test(`shared password policy rejects ${label}`, async () => {
    const f = fixture();
    const result = await routeRequest(f.router, {
      token: tokenFor('SUPER_ADMIN'), body: { ...validBody, password }
    });
    assert.equal(result.status, 400);
    assert.equal(f.queries.length, 0);
    assert.equal(f.hashes.length, 0);
  });
}

test('shared policy accepts 12 Unicode characters within the bcrypt byte limit', async () => {
  const f = fixture();
  const result = await routeRequest(f.router, {
    token: tokenFor('SUPER_ADMIN'),
    body: { ...validBody, password: '\u{1F510}'.repeat(12) }
  });
  assert.equal(result.status, 201);
});

test('missing request fields are rejected without database work', async () => {
  const f = fixture();
  assert.equal((await routeRequest(f.router, {
    token: tokenFor('SUPER_ADMIN'), body: {}
  })).status, 400);
  assert.equal(f.queries.length, 0);
});

test('duplicate email remains a conflict without hashing or insertion', async () => {
  const f = fixture({ duplicate: true });
  assert.equal((await routeRequest(f.router, {
    token: tokenFor('SUPER_ADMIN')
  })).status, 409);
  assert.equal(f.queries.length, 1);
  assert.equal(f.hashes.length, 0);
});

// Exercise ordinary admin handlers with empty mocked records. A 404 here means
// authorisation passed but the requested synthetic record does not exist.
const ordinaryHandlers = [
  ['Item Management', 'item_controller.js', 'getAllItems', {}, 200],
  ['Claim Review list', 'claim_controller.js', 'getAllClaims', {}, 200],
  ['Claim Review decision', 'admin_verification_controller.js', 'verifyClaim', {
    params: { claimId: '1' }, body: { decision: 'APPROVED', answers: [{}, {}] }
  }, 404],
  ['OTP generation', 'otp_controller.js', 'generateOtp', { params: { claimId: '1' } }, 404],
  ['OTP Collection lookup', 'collection_controller.js', 'lookupCollection', {
    body: { otp_code: '123456' }
  }, 404],
  ['OTP Collection confirmation', 'collection_controller.js', 'confirmCollection', {
    body: { otp_code: '123456', claim_id: 1 }
  }, 404],
  ['Retention', 'retention_controller.js', 'getRetentionRecords', {}, 200],
  ['Disposal', 'disposal_controller.js', 'getDisposalRecords', {}, 200],
  ['Audit Logs', 'audit_log_controller.js', 'getAuditLogs', {}, 200],
  ['System Settings', 'system_setting_controller.js', 'getRetentionSetting', {}, 404],
  ['HIGH publication review', 'item_publication_controller.js', 'getPendingHighValueReports', {}, 200]
];

for (const role of ['ADMIN', 'SUPER_ADMIN']) {
  for (const [label, file, handler, request, expectedStatus] of ordinaryHandlers) {
    test(`${role} retains ordinary access: ${label}`, async () => {
      let queryCount = 0;
      const connection = {
        async query() { queryCount++; return [[]]; },
        async beginTransaction() {}, async commit() {}, async rollback() {}, release() {}
      };
      const pool = { ...connection, async getConnection() { return connection; } };
      const lifecycle = loadModule('services/item_lifecycle_service.js', {
        '../config/db': pool,
        './audit_log_service': { async createAuditLog() {} }
      });
      const controller = loadModule(`controllers/${file}`, {
        '../services/item_lifecycle_service': lifecycle,
        '../config/db': pool,
        '../services/audit_log_service': { async createAuditLog() {} },
        '../services/notification_service': { async createNotification() {} },
        '../services/automatic_matching_service': { triggerMatching() {} },
        '../controllers/otp_controller': {}
      });
      const res = response();
      await controller[handler]({
        params: {}, body: {}, user: { user_id: 1, role }, ...request
      }, res);
      assert.equal(res.statusCode, expectedStatus);
      assert.ok(queryCount > 0, 'handler must pass its role guard and reach mocked persistence');
    });
  }
}
