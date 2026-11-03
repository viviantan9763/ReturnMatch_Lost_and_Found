const fs = require('node:fs/promises');
const path = require('node:path');
const { createHash } = require('node:crypto');
const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads'));
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
function imageType(bytes) {
  if (!Buffer.isBuffer(bytes) || !bytes.length || bytes.length > MAX_IMAGE_BYTES) return null;
  if (bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) return { mime: 'image/png', extension: '.png' };
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return { mime: 'image/jpeg', extension: '.jpg' };
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return { mime: 'image/webp', extension: '.webp' };
  return null;
}
function validateImage(file) {
  const type = imageType(file?.buffer);
  if (!type || type.mime !== file.mimetype) {
    const error = new Error('Upload a valid JPEG, PNG or WEBP image, no larger than 5 MB.');
    error.status = 400;
    throw error;
  }
  return type;
}
function storedPath(imagePath) {
  if (typeof imagePath !== 'string' || !/^uploads\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/.test(imagePath)) throw new Error('Invalid stored image reference');
  const file = path.resolve(UPLOAD_DIR, path.basename(imagePath));
  if (path.dirname(file) !== UPLOAD_DIR) throw new Error('Invalid image path');
  return file;
}
async function readImage(imagePath) {
  const file = storedPath(imagePath);
  const [realFile, realRoot] = await Promise.all([fs.realpath(file), fs.realpath(UPLOAD_DIR)]);
  if (path.dirname(realFile) !== realRoot) throw new Error('Image must stay within upload storage');
  const stat = await fs.stat(realFile);
  if (!stat.isFile() || stat.size > MAX_IMAGE_BYTES) throw new Error('Invalid image file');
  const buffer = await fs.readFile(realFile);
  const type = imageType(buffer);
  if (!type) throw new Error('Invalid stored image');
  return { buffer, mime: type.mime, name: path.basename(file) };
}
function imageReference(itemId, file) {
  const type = validateImage(file);
  return `uploads/${itemId}-${createHash('sha256').update(file.buffer).digest('hex')}${type.extension}`;
}
async function storeImage(imagePath, buffer) {
  await fs.mkdir(UPLOAD_DIR, { recursive: true, mode: 0o700 });
  try {
    await fs.writeFile(storedPath(imagePath), buffer, { flag: 'wx', mode: 0o600 });
    return true;
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
    if (!(await readImage(imagePath)).buffer.equals(buffer)) throw new Error('Stored image content does not match');
    return false;
  }
}
async function removeImage(imagePath) { await fs.unlink(storedPath(imagePath)); }
module.exports = { UPLOAD_DIR, MAX_IMAGE_BYTES, imageType, validateImage, imageReference, storeImage, readImage, removeImage };
