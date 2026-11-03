// Tests actual controllers with in-memory persistence; never loads .env or MySQL.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const { createRequire } = require('node:module');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadController(name, pool) {
  const filename = path.resolve(__dirname, '../controllers', name);
  const localRequire = createRequire(filename);
  const module = { exports: {} };
  const evaluate = vm.compileFunction(fs.readFileSync(filename, 'utf8'),
    ['module', 'require', 'console'], { filename });
  evaluate(module, (dependency) => {
    if (dependency === '../config/db') return pool;
    if (dependency === '../controllers/otp_controller') return {};
    return localRequire(dependency);
  }, { error() {} });
  return module.exports;
}

const digest = value => crypto.createHash('sha256').update(value.trim().toLowerCase()).digest('hex');
const submitted = [
  { question_no: 1, answer_text: ' synthetic contents ' },
  { question_no: 2, answer_text: 'synthetic engraving' }
];

function fixture({ tier = 'HIGH', status = 'PENDING', claimantId = 7,
  questionsMissing = false, failInsert = false } = {}) {
  const item = { item_id: 55, item_name: 'Synthetic item', item_type: 'FOUND',
    reporter_id: 8, publication_status: 'PUBLISHED', status: 'ACTIVE', value_tier: tier };
  const questions = [
    { question_no: 1, question_text: 'What is inside the hidden pocket?', answer_hash: digest('synthetic contents') },
    { question_no: 2, question_text: 'What is the concealed engraving?', answer_hash: digest('synthetic engraving') }
  ];
  const state = { claims: [], answers: [], calls: [], commits: 0, rollbacks: 0 };
  let snapshot;
  const pool = {
    async query(sql, parameters = []) {
      const flat = sql.replace(/\s+/g, ' ').trim();
      state.calls.push({ sql: flat, parameters });
      if (/^INSERT INTO claim /.test(flat)) {
        const claim = { claim_id: 101 + state.claims.length, item_id: parameters[0],
          claimant_id: parameters[1], claim_status: 'PENDING' };
        state.claims.push(claim);
        return [{ insertId: claim.claim_id }];
      }
      if (/^SELECT claim_id FROM claim/.test(flat)) {
        const own = flat.includes('claimant_id');
        return [state.claims.filter(claim => claim.item_id === parameters[0] &&
          (own ? claim.claimant_id === parameters[1] &&
            ['PENDING', 'UNDER_REVIEW', 'VERIFICATION_REQUIRED', 'APPROVED'].includes(claim.claim_status)
            : ['APPROVED', 'COLLECTED'].includes(claim.claim_status)))];
      }
      if (/FROM item WHERE item_id/.test(flat)) return [[item]];
      if (/FROM claim c JOIN item i/.test(flat)) {
        const claim = state.claims.find(claim => claim.claim_id === Number(parameters[0]));
        return [claim ? [{ ...claim, value_tier: tier, item_status: item.status,
          item_type: item.item_type, publication_status: item.publication_status,
          item_name: item.item_name }] : []];
      }
      if (/FROM item_security_question/.test(flat)) {
        return [questionsMissing ? [] : questions.map(question => flat.includes('answer_hash')
          ? question : { question_no: question.question_no, question_text: question.question_text })];
      }
      if (/SELECT answer_id FROM security_answer/.test(flat)) {
        return [state.answers.filter(answer => answer.claim_id === Number(parameters[0]))];
      }
      if (/^INSERT INTO security_answer/.test(flat)) {
        if (failInsert) throw new Error('Synthetic insert failure');
        state.answers.push({ answer_id: state.answers.length + 1, claim_id: parameters[0],
          question_no: parameters[1], question_text: parameters[2], answer_text: parameters[3],
          is_correct: parameters[4] });
        return [{ insertId: state.answers.length }];
      }
      if (/^UPDATE claim SET claim_status=/.test(flat)) {
        const id = Number(parameters[0]);
        state.claims.find(claim => claim.claim_id === id).claim_status =
          flat.includes("claim_status='APPROVED'") ? 'APPROVED' : 'VERIFICATION_REQUIRED';
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Unexpected mocked SQL: ${flat}`);
    },
    async getConnection() { return this; },
    async beginTransaction() {
      snapshot = structuredClone({ claims: state.claims, answers: state.answers });
    },
    async commit() { state.commits++; snapshot = undefined; },
    async rollback() {
      state.rollbacks++;
      if (snapshot) { state.claims = snapshot.claims; state.answers = snapshot.answers; snapshot = undefined; }
    },
    release() {}
  };
  function seedClaim() {
    const claim = { claim_id: 101, claimant_id: claimantId, item_id: 55, claim_status: status };
    state.claims.push(claim);
    return claim;
  }
  return { state, item, questions, seedClaim,
    claims: loadController('claim_controller.js', pool),
    security: loadController('security_answer_controller.js', pool) };
}

async function call(handler, { claimId = '101', userId = 7, body = {} } = {}) {
  const response = {
    statusCode: 200,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; }
  };
  await handler({ user: { user_id: userId, role: 'USER' }, params: { claimId }, body }, response);
  return response;
}

for (const tier of ['HIGH', 'MEDIUM']) {
  test(`${tier} creation is PENDING; client-supplied approval/tier is ignored`, async () => {
    const f = fixture({ tier });
    const response = await call(f.claims.createClaim, {
      body: { item_id: 55, claim_reason: 'Synthetic reason', claim_status: 'APPROVED', value_tier: 'MEDIUM' }
    });
    assert.equal(response.statusCode, 201);
    assert.equal(response.body.claim.claim_status, 'PENDING');
    assert.equal(response.body.claim.value_tier, tier);
    assert.equal(f.state.claims.length, 1);
  });
}

test('duplicate active claim is rejected without a second insert', async () => {
  const f = fixture();
  f.seedClaim();
  const response = await call(f.claims.createClaim, { body: { item_id: 55 } });
  assert.equal(response.statusCode, 409);
  assert.equal(f.state.claims.length, 1);
  assert.ok(!f.state.calls.some(call => call.sql.startsWith('INSERT')));
});

test('question API returns actual numbered text, never reference hashes', async () => {
  const f = fixture();
  f.seedClaim();
  const response = await call(f.security.getSecurityQuestions);
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.questions, f.questions.map(({ question_no, question_text }) => ({ question_no, question_text })));
  assert.ok(!JSON.stringify(response.body).includes('answer_hash'));
});

test('another user cannot retrieve ownership questions', async () => {
  const f = fixture();
  f.seedClaim();
  const response = await call(f.security.getSecurityQuestions, { userId: 99 });
  assert.equal(response.statusCode, 403);
  assert.equal(f.state.calls.length, 1);
});

for (const [name, answers] of [
  ['old three unnumbered answers', [{ answer_text: 'one' }, { answer_text: 'two' }, { answer_text: 'three' }]],
  ['one answer', [submitted[0]]],
  ['duplicate numbers', [submitted[0], submitted[0]]],
  ['unknown number', [submitted[0], { question_no: 3, answer_text: 'value' }]],
  ['empty answer', [submitted[0], { question_no: 2, answer_text: ' ' }]],
  ['short answer', [submitted[0], { question_no: 2, answer_text: 'x' }]],
  ['overlength answer', [submitted[0], { question_no: 2, answer_text: 'x'.repeat(251) }]],
  ['non-text answer', [submitted[0], { question_no: 2, answer_text: 123 }]]
]) {
  test(`${name} is rejected before database work`, async () => {
    const f = fixture();
    const response = await call(f.security.submitSecurityAnswers, { body: { answers } });
    assert.equal(response.statusCode, 400);
    assert.equal(f.state.calls.length, 0);
  });
}

for (const [tier, correct, expected] of [
  ['HIGH', true, 'VERIFICATION_REQUIRED'],
  ['HIGH', false, 'VERIFICATION_REQUIRED'],
  ['MEDIUM', true, 'APPROVED'],
  ['MEDIUM', false, 'VERIFICATION_REQUIRED']
]) {
  test(`${tier}, answers ${correct ? 'matching' : 'not matching'}: existing policy gives ${expected}`, async () => {
    const f = fixture({ tier });
    f.seedClaim();
    const answers = correct ? submitted : [submitted[0], { question_no: 2, answer_text: 'different evidence' }];
    const response = await call(f.security.submitSecurityAnswers, { body: { answers } });
    assert.equal(response.statusCode, 201);
    assert.equal(response.body.claim.claim_status, expected);
    assert.equal(f.state.claims[0].claim_status, expected);
    assert.equal(f.state.answers.length, 2);
    assert.equal(f.state.answers[0].question_text, f.questions[0].question_text);
    assert.equal(f.state.commits, 1);
  });
}

test('other user cannot submit answers', async () => {
  const f = fixture();
  f.seedClaim();
  assert.equal((await call(f.security.submitSecurityAnswers, { userId: 99, body: { answers: submitted } })).statusCode, 403);
  assert.equal(f.state.answers.length, 0);
});

test('missing stored questions cannot complete verification', async () => {
  const f = fixture({ questionsMissing: true });
  f.seedClaim();
  assert.equal((await call(f.security.submitSecurityAnswers, { body: { answers: submitted } })).statusCode, 409);
  assert.equal(f.state.answers.length, 0);
  assert.equal(f.state.claims[0].claim_status, 'PENDING');
});

test('repeat submission cannot overwrite saved answers', async () => {
  const f = fixture();
  f.seedClaim();
  assert.equal((await call(f.security.submitSecurityAnswers, { body: { answers: submitted } })).statusCode, 201);
  assert.equal((await call(f.security.submitSecurityAnswers, { body: { answers: submitted } })).statusCode, 409);
  assert.equal(f.state.answers.length, 2);
  assert.equal(f.state.claims.length, 1);
});

test('answer persistence failure rolls back without deleting or recreating the claim', async () => {
  const f = fixture({ failInsert: true });
  f.seedClaim();
  assert.equal((await call(f.security.submitSecurityAnswers, { body: { answers: submitted } })).statusCode, 500);
  assert.equal(f.state.answers.length, 0);
  assert.equal(f.state.claims.length, 1);
  assert.equal(f.state.claims[0].claim_id, 101);
  assert.equal(f.state.claims[0].claim_status, 'PENDING');
  assert.equal(f.state.rollbacks, 1);
});

test('terminal item cannot accept ownership answers', async () => {
  const f = fixture();
  f.seedClaim();
  f.item.status = 'CLAIMED';
  assert.equal((await call(f.security.submitSecurityAnswers, { body: { answers: submitted } })).statusCode, 409);
  assert.equal(f.state.answers.length, 0);
});
