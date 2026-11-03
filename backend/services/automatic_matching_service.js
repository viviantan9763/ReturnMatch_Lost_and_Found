// ReturnMatch Phase 3B: compares published, active Lost/Found pairs.
// Node.js 18+ required for fetch/FormData/Blob. Python FastAPI on localhost:8001.
const pool = require('../config/db');
const fs = require('node:fs/promises');
const path = require('node:path');

const AI_URL = process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001';
const MATCH_THRESHOLD = Number(process.env.MATCH_THRESHOLD || 0.72); // provisional, evaluate on test data
const UPLOAD_DIR = path.resolve(process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads'));
const ALLOWED_STATUSES = ['ACTIVE', 'MATCHED', 'CLAIM_PENDING'];
const running = new Set();

async function imageBlob(imagePath) {
  if (!imagePath) return null;
  // Database paths are always uploads/<filename>; never trust arbitrary paths.
  const normalized = String(imagePath).replace(/\\/g, '/');
  if (!/^uploads\/[A-Za-z0-9_.-]+$/.test(normalized)) return null;
  const file = path.resolve(UPLOAD_DIR, path.basename(normalized));
  if (path.dirname(file) !== UPLOAD_DIR) return null;
  try {
    const stat = await fs.stat(file);
    if (!stat.isFile() || stat.size > 10 * 1024 * 1024) return null;
    const extension = path.extname(file).toLowerCase();
    const mime = { '.jpg':'image/jpeg', '.jpeg':'image/jpeg', '.png':'image/png', '.webp':'image/webp' }[extension];
    if (!mime) return null;
    return { blob: new Blob([await fs.readFile(file)], { type: mime }), name: path.basename(file) };
  } catch (e) {
    if (e.code !== 'ENOENT') console.warn('[matching] image unavailable:', e.message);
    return null;
  }
}

async function comparePair(lost, found) {
  const form = new FormData();
  const fields = {
    lost_category: lost.category_name, found_category: found.category_name,
    lost_description: [lost.item_name, lost.description].filter(Boolean).join(' '),
    found_description: [found.item_name, found.description].filter(Boolean).join(' '),
    lost_model: lost.model_info, found_model: found.model_info,
    lost_colour: lost.colour, found_colour: found.colour
  };
  for (const [key,value] of Object.entries(fields)) form.set(key, String(value || ''));
  const [a,b] = await Promise.all([imageBlob(lost.image_path), imageBlob(found.image_path)]);
  if (a && b) {
    form.set('lost_image', a.blob, a.name);
    form.set('found_image', b.blob, b.name);
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 120000);
  try {
    const response = await fetch(`${AI_URL}/hybrid-match`, {
      method:'POST', body:form, signal:controller.signal
    });
    if (!response.ok) throw new Error(`AI service returned HTTP ${response.status}`);
    return await response.json();
  } finally { clearTimeout(timer); }
}

const ITEM_QUERY = `
  SELECT i.item_id, i.reporter_id, i.item_type, i.category_id, c.category_name,
         i.item_name, i.description, i.model_info, i.colour,
         i.location, i.event_date, i.status, i.publication_status,
         (SELECT ii.image_path FROM item_image ii WHERE ii.item_id=i.item_id
          ORDER BY (ii.image_role='PRIMARY') DESC, ii.uploaded_at ASC LIMIT 1) image_path
  FROM item i LEFT JOIN item_category c ON c.category_id=i.category_id`;

async function runMatchingForItem(itemId) {
  const id = Number(itemId);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid item ID');
  if (running.has(id)) return { skipped:'already_running' };
  running.add(id);
  const stats = { compared:0, saved:0, notified:0, skipped:0, errors:0 };
  try {
    const [[source]] = await pool.query(`${ITEM_QUERY} WHERE i.item_id=?`, [id]);
    if (!source || source.publication_status !== 'PUBLISHED' || !ALLOWED_STATUSES.includes(source.status)) {
      return { ...stats, skipped_reason:'item_not_public' };
    }
    const opposite = source.item_type === 'LOST' ? 'FOUND' : 'LOST';
    const [candidates] = await pool.query(
      `${ITEM_QUERY} WHERE i.item_type=? AND i.category_id=? AND i.item_id<>?
       AND i.reporter_id<>? AND i.publication_status='PUBLISHED'
       AND i.status IN ('ACTIVE','MATCHED','CLAIM_PENDING')
       ORDER BY i.reported_at DESC LIMIT 100`,
      [opposite, source.category_id, id, source.reporter_id]
    );
    for (const candidate of candidates) {
      const lost = source.item_type === 'LOST' ? source : candidate;
      const found = source.item_type === 'FOUND' ? source : candidate;
      try {
        const result = await comparePair(lost, found);
        stats.compared++;
        const overall = result.overall_similarity_score;
        const count = Number(result.evidence_components_available || 0);
        if (result.status === 'category_mismatch' || overall == null || count < 2 ||
            result.model_conflict || Number(overall) < MATCH_THRESHOLD) {
          stats.skipped++;
          continue;
        }
        const score = (key) => result.component_scores?.[key] ?? null;
        const conn = await pool.getConnection();
        try {
          await conn.beginTransaction();
          // Preserve existing REJECTED / CONFIRMED status on recomputation.
          const [insert] = await conn.query(`
            INSERT INTO match_result
              (lost_item_id,found_item_id,image_similarity,text_similarity,
               model_similarity,colour_similarity,category_similarity,
               location_similarity,date_similarity,overall_similarity,match_status)
            VALUES (?,?,?,?,?,?,?,NULL,NULL,?,'SUGGESTED')
            ON DUPLICATE KEY UPDATE
              image_similarity=VALUES(image_similarity),text_similarity=VALUES(text_similarity),
              model_similarity=VALUES(model_similarity),colour_similarity=VALUES(colour_similarity),
              category_similarity=VALUES(category_similarity),overall_similarity=VALUES(overall_similarity)
          `,[lost.item_id,found.item_id,score('image'),score('text'),score('model'),
             score('colour'),1,overall]);
          // Only first insertion sends notification. Unique pair index prevents races.
          if (insert.affectedRows === 1) {
            await conn.query(`INSERT INTO notification
              (user_id,item_id,claim_id,notification_type,message)
              VALUES (?, ?, NULL, 'MATCH_SUGGESTED', ?)`, [
                lost.reporter_id, lost.item_id,
                `A possible match was found for your lost item report #${lost.item_id}. Check My Matches.`
              ]);
            stats.notified++;
          }
          await conn.commit();
          stats.saved++;
        } catch(e) { await conn.rollback(); throw e; }
        finally { conn.release(); }
      } catch(e) { stats.errors++; console.error('[matching] pair failed:', lost.item_id, found.item_id, e.message); }
    }
    return stats;
  } finally { running.delete(id); }
}

function triggerMatching(itemId) {
  // Best effort; manual POST /api/matches/items/:itemId/run supports retry.
  setImmediate(() => runMatchingForItem(itemId).then(
    r => console.log('[matching]', itemId, r),
    e => console.error('[matching] trigger failed:', itemId, e.message)
  ));
}

module.exports = { runMatchingForItem, triggerMatching };
