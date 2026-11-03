// Shared password policy for registration and authenticated password changes.
// This is a basic blocklist, not a complete breached-password database.
const COMMON_PASSWORDS = new Set([
  'password123',
  'password1234',
  'password12345',
  '123456789012',
  '1234567890123',
  'qwerty123456',
  'qwertyuiop123',
  'admin12345678',
  'letmein123456',
  'iloveyou1234',
]);

function passwordPolicyError(password) {
  if (typeof password !== 'string') {
    return 'Password must be text';
  }
  if (Array.from(password).length < 12) {
    return 'Password must be at least 12 characters';
  }
  // bcrypt hashes only the first 72 UTF-8 bytes. Do not silently truncate.
  if (Buffer.byteLength(password, 'utf8') > 72) {
    return 'Password must not exceed 72 UTF-8 bytes';
  }
  if (COMMON_PASSWORDS.has(password.toLowerCase().trim())) {
    return 'Password is too common; choose a less predictable password';
  }
  return null;
}

module.exports = { passwordPolicyError };
