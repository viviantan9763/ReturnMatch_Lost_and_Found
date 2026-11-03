// ReturnMatch Phase 3B: compares published, active Lost/Found pairs.
// Node.js 18+ required for fetch/FormData/Blob. Python FastAPI on localhost:8001.
const pool = require('../config/db');
const { readImage } = require('./image_storage_service');
const AI_URL = (process.env.AI_SERVICE_URL || 'http://127.0.0.1:8001').replace(/\/$/, '');
const MATCH_THRESHOLD = Number(process.env.MATCH_THRESHOLD || 0.72);
const ALLOWED_STATUSES = ['ACTIVE', 'MATCHED', 'CLAIM_PENDING'];
const running = new Map();
const rerun = new Set();
// Upload intent is process-local because the current schema has no upload state.
// Block the first-image window without changing publication/lifecycle ENUMs.
const pendingImages = new Set();
const markImagePending = id => pendingImages.add(Number(id));
const markImageReady = id => pendingImages.delete(Number(id));
async function imageBlob(imagePath) {
  if (!imagePath) return null;
  // A referenced but missing/corrupt image is a retryable failure, not evidence
  // that the image score should silently be omitted from the existing weights.
  const image = await readImage(imagePath);
  return { blob: new Blob([image.buffer], { type: image.mime }), name: image.name };
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
  if (a) form.set('lost_image', a.blob, a.name);
  if (b) form.set('found_image', b.blob, b.name);
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
         (SELECT COUNT(*) FROM disposal_record d WHERE d.item_id=i.item_id AND d.disposal_status IN ('PENDING','COMPLETED')) blocking_disposal_count,
         (SELECT ii.image_path FROM item_image ii WHERE ii.item_id=i.item_id
          ORDER BY (ii.image_role='PRIMARY') DESC, ii.image_id ASC LIMIT 1) image_path
  FROM item i LEFT JOIN item_category c ON c.category_id=i.category_id`;

async function matchingPass(itemId) {
  const id = Number(itemId);
  if (!Number.isSafeInteger(id) || id <= 0) throw new Error('Invalid item ID');

  const stats = { compared:0, saved:0, notified:0, skipped:0, errors:0 };
  if (pendingImages.has(id)) return { ...stats, skipped_reason: 'image_upload_pending' };
  const [[source]] = await pool.query(`${ITEM_QUERY} WHERE i.item_id=?`, [id]);
  if (!source || !['LOST','FOUND'].includes(source.item_type) || source.publication_status !== 'PUBLISHED' || Number(source.blocking_disposal_count) > 0 || !ALLOWED_STATUSES.includes(source.status)) {
    return { ...stats, skipped_reason:'item_not_public' };
  }
  const opposite = source.item_type === 'LOST' ? 'FOUND' : 'LOST';
  const [candidates] = await pool.query(
    `${ITEM_QUERY} WHERE i.item_type=? AND i.category_id=? AND i.item_id<>?
     AND i.reporter_id<>? AND i.publication_status='PUBLISHED'
     AND i.status IN ('ACTIVE','MATCHED','CLAIM_PENDING')
     AND NOT EXISTS (SELECT 1 FROM disposal_record d WHERE d.item_id=i.item_id AND d.disposal_status IN ('PENDING','COMPLETED'))
     ORDER BY i.reported_at DESC LIMIT 100`,
    [opposite, source.category_id, id, source.reporter_id]
  );
  for (const candidate of candidates) {
    if (pendingImages.has(Number(candidate.item_id))) { stats.skipped++; continue; }
    const lost = source.item_type === 'LOST' ? source : candidate;
    const found = source.item_type === 'FOUND' ? source : candidate;
    try {
      const result = await comparePair(lost, found);
      stats.compared++;
      const overall = result.overall_similarity_score;
      const scores = result.component_scores;
      const validScore = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1;
      if (result.success !== true || !scores || typeof scores !== 'object' ||
          (overall !== null && !validScore(overall)) ||
          ['image','text','model','colour'].some(key => scores[key] != null && !validScore(scores[key]))) {
        throw new Error('AI returned malformed similarity scores');
      }
      const count = ['image','text','model','colour'].filter(key => scores[key] != null).length;
      const suggested = result.status !== 'category_mismatch' && overall !== null && count >= 2 && !result.model_conflict && overall >= MATCH_THRESHOLD;
      const score = key => scores[key] ?? null;
      const conn = await pool.getConnection();
      try {
        await conn.beginTransaction();
        // Recheck the exact evidence and current visibility after the slow AI
        // request. Lock both items in stable order, as lifecycle writers do.
        const [current] = await conn.query(`${ITEM_QUERY} WHERE i.item_id IN (?,?) ORDER BY i.item_id FOR UPDATE`, [lost.item_id, found.item_id]);
        const lockedLost = current.find(i => Number(i.item_id) === Number(lost.item_id));
        const lockedFound = current.find(i => Number(i.item_id) === Number(found.item_id));
        for (const item of current) {
          const [[image]] = await conn.query(`SELECT image_path FROM item_image WHERE item_id=?
            ORDER BY (image_role='PRIMARY') DESC,image_id ASC LIMIT 1 FOR UPDATE`, [item.item_id]);
          item.image_path = image?.image_path || null;
        }
        const evidence = item => JSON.stringify(['item_id','reporter_id','item_type','category_id','category_name','item_name','description','model_info','colour','image_path'].map(key => item[key] ?? null));
        const eligible = item => item && item.publication_status === 'PUBLISHED' && ALLOWED_STATUSES.includes(item.status);
        const [disposals] = await conn.query(`SELECT disposal_id FROM disposal_record WHERE item_id IN (?,?)
          AND disposal_status IN ('PENDING','COMPLETED') ORDER BY disposal_id FOR UPDATE`, [lost.item_id, found.item_id]);
        if (!eligible(lockedLost) || !eligible(lockedFound) || disposals.length ||
            evidence(lockedLost) !== evidence(lost) || evidence(lockedFound) !== evidence(found)) {
          await conn.rollback(); stats.skipped++; continue;
        }
        const [existing] = await conn.query(`SELECT match_id,match_status FROM match_result
          WHERE lost_item_id=? AND found_item_id=? ORDER BY match_id FOR UPDATE`, [lost.item_id, found.item_id]);
        if (existing.length > 1) throw new Error('Historical duplicate match pairs require manual review');
        if (existing[0]?.match_status && existing[0].match_status !== 'SUGGESTED') {
          await conn.commit(); stats.skipped++; continue;
        }
        if (!suggested && !existing.length) { await conn.commit(); stats.skipped++; continue; }
        const values = [score('image'),score('text'),score('model'),score('colour'),result.category_compatible === true ? 1 : null,
          suggested ? overall : (overall !== null && count >= 2 && !result.model_conflict ? overall : null)];
        if (existing.length) {
          // Keep history, but stale suggestions below the threshold will no
          // longer be returned by recommendation APIs.
          await conn.query(`UPDATE match_result SET image_similarity=?,text_similarity=?,model_similarity=?,
            colour_similarity=?,category_similarity=?,overall_similarity=? WHERE match_id=? AND match_status='SUGGESTED'`, [...values, existing[0].match_id]);
        } else {
          await conn.query(`INSERT INTO match_result
            (lost_item_id,found_item_id,image_similarity,text_similarity,model_similarity,colour_similarity,
             category_similarity,location_similarity,date_similarity,overall_similarity,match_status)
            VALUES (?,?,?,?,?,?,?,NULL,NULL,?,'SUGGESTED')`, [lost.item_id,found.item_id,...values]);
          await conn.query(`INSERT INTO notification (user_id,item_id,claim_id,notification_type,message)
            VALUES (?,?,NULL,'MATCH_SUGGESTED',?)`, [lost.reporter_id,lost.item_id,
            `A possible match was found for your lost item report #${lost.item_id}. Check My Matches.`]);
        }
        await conn.commit();
        stats.saved++;
        if (!existing.length) stats.notified++;
      } catch(e) { await conn.rollback(); throw e; }
      finally { conn.release(); }
    } catch(e) { stats.errors++; console.error('[matching] pair failed:', lost.item_id, found.item_id, e.message); }
  }
  return stats;
}

function runMatchingForItem(itemId) {
  const id = Number(itemId);
  if (!Number.isSafeInteger(id) || id <= 0) return Promise.reject(new Error('Invalid item ID'));
  if (running.has(id)) { rerun.add(id); return running.get(id); }
  const work = (async () => {
    let result;
    do { rerun.delete(id); result = await matchingPass(id); } while (rerun.has(id));
    return result;
  })().finally(() => { running.delete(id); rerun.delete(id); });
  running.set(id, work);
  return work;
}
function triggerMatching(itemId) {
  setImmediate(() => runMatchingForItem(itemId).then(
    r => console.log('[matching]', itemId, r),
    e => console.error('[matching] trigger failed:', itemId, e.message)
  ));
}
module.exports = { runMatchingForItem, triggerMatching, markImagePending, markImageReady };
