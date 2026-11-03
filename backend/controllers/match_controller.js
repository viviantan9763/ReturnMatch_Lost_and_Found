
const pool = require('../config/db');
const { runMatchingForItem } = require('../services/automatic_matching_service');
const isAdmin = u => u && ['ADMIN','SUPER_ADMIN'].includes(u.role);

const MATCH_THRESHOLD = Number(process.env.MATCH_THRESHOLD || 0.72);
const PUBLIC = `lost.publication_status='PUBLISHED' AND found.publication_status='PUBLISHED'
 AND lost.status IN ('ACTIVE','MATCHED','CLAIM_PENDING')
 AND found.status IN ('ACTIVE','MATCHED','CLAIM_PENDING')
 AND NOT EXISTS (SELECT 1 FROM disposal_record d WHERE d.item_id IN (lost.item_id,found.item_id) AND d.disposal_status IN ('PENDING','COMPLETED'))
 AND (mr.match_status <> 'SUGGESTED' OR mr.overall_similarity >= ${MATCH_THRESHOLD})`;

const getMyMatchSuggestions = async (req,res) => {
  try {
    const [matches] = await pool.query(`
      SELECT mr.match_id,mr.lost_item_id,mr.found_item_id,
        mr.image_similarity,mr.text_similarity,mr.model_similarity,
        mr.colour_similarity,mr.category_similarity,mr.location_similarity,
        mr.date_similarity,mr.overall_similarity,mr.match_status,mr.created_at,
        lost.item_name AS lost_item_name,
        CASE WHEN found.value_tier='HIGH' THEN COALESCE(c.category_name,'High-value found item')
             ELSE found.item_name END AS found_item_name,
        found.location AS found_location,found.value_tier AS found_value_tier,
        found.status AS found_status,found.event_date AS found_event_date
      FROM match_result mr
      JOIN item lost ON lost.item_id=mr.lost_item_id
      JOIN item found ON found.item_id=mr.found_item_id
      LEFT JOIN item_category c ON c.category_id=found.category_id
      WHERE lost.reporter_id=? AND lost.item_type='LOST' AND found.item_type='FOUND'
        AND mr.match_status='SUGGESTED' AND ${PUBLIC}
      ORDER BY mr.overall_similarity DESC,mr.created_at DESC`,[req.user.user_id]);
    return res.json({matches});
  } catch(e) { console.error('Get matches error',e); return res.status(500).json({message:'Failed to load match suggestions'}); }
};

const getMatchById = async (req,res) => {
  const id = Number(req.params.matchId);
  if (!Number.isSafeInteger(id) || id<=0) return res.status(400).json({message:'Invalid match ID'});
  try {
    const admin=isAdmin(req.user);
    const [matches] = await pool.query(`
      SELECT mr.*,lost.reporter_id AS lost_reporter_id,
        lost.item_name AS lost_item_name,lost.description AS lost_description,
        lost.location AS lost_location,
        found.value_tier AS found_value_tier,found.status AS found_status,
        CASE WHEN found.value_tier='HIGH' AND ?=0 THEN COALESCE(c.category_name,'High-value found item')
             ELSE found.item_name END AS found_item_name,
        CASE WHEN found.value_tier='HIGH' AND ?=0 THEN NULL ELSE found.description END AS found_description,
        found.location AS found_location
      FROM match_result mr JOIN item lost ON lost.item_id=mr.lost_item_id
      JOIN item found ON found.item_id=mr.found_item_id
      LEFT JOIN item_category c ON c.category_id=found.category_id
      WHERE mr.match_id=? AND lost.item_type='LOST' AND found.item_type='FOUND'
        AND (?=1 OR lost.reporter_id=?) AND (?=1 OR (${PUBLIC}))
      LIMIT 1`,[admin?1:0,admin?1:0,id,admin?1:0,req.user.user_id,admin?1:0]);
    if (!matches.length) return res.status(404).json({message:'Match not found'});
    delete matches[0].lost_reporter_id;
    return res.json({match:matches[0]});
  } catch(e) { console.error('Get match error',e); return res.status(500).json({message:'Failed to load match'}); }
};

const runItemMatching = async (req,res) => {
  const id=Number(req.params.itemId);
  if (!Number.isSafeInteger(id)||id<=0) return res.status(400).json({message:'Invalid item ID'});
  try {
    const [[item]]=await pool.query('SELECT reporter_id FROM item WHERE item_id=?',[id]);
    if (!item) return res.status(404).json({message:'Item not found'});
    if (!isAdmin(req.user) && Number(item.reporter_id)!==Number(req.user.user_id))
      return res.status(403).json({message:'Not allowed to match this item'});
    const result=await runMatchingForItem(id);
    if (result.skipped_reason === 'image_upload_pending') return res.status(409).json({message:'Finish uploading this report image before matching.',result});
    if (result.errors > 0) return res.status(503).json({message:'Report saved, but matching is incomplete. Retry matching for this report.',result});
    return res.json({message:'Matching attempt completed',result});
  } catch(e) { console.error('Run matching error',e); return res.status(503).json({message:'Matching service unavailable'}); }
};
module.exports={getMyMatchSuggestions,getMatchById,runItemMatching};



/* const pool = require('../config/db');

// ----------------------------------------------------
// GET CURRENT USER MATCH SUGGESTIONS
// GET /api/matches/my
// ----------------------------------------------------

const getMyMatchSuggestions = async (req, res) => {
  try {
    const userId = req.user.user_id;

    const [matches] = await pool.query(
      `
      SELECT
        mr.match_id,
        mr.lost_item_id,
        mr.found_item_id,

        mr.image_similarity,
        mr.text_similarity,
        mr.category_similarity,
        mr.location_similarity,
        mr.date_similarity,
        mr.overall_similarity,

        mr.match_status,
        mr.created_at,

        lost.item_name AS lost_item_name,

        found.item_name AS found_item_name,
        found.location AS found_location,
        found.value_tier AS found_value_tier,
        found.status AS found_status,
        found.event_date AS found_event_date

      FROM match_result mr

      JOIN item lost
        ON mr.lost_item_id = lost.item_id

      JOIN item found
        ON mr.found_item_id = found.item_id

      WHERE lost.reporter_id = ?
        AND lost.item_type = 'LOST'
        AND found.item_type = 'FOUND'
        AND mr.match_status = 'SUGGESTED'

      ORDER BY
        mr.overall_similarity DESC,
        mr.created_at DESC
      `,
      [userId]
    );

    return res.status(200).json({
      matches
    });

  } catch (error) {
    console.error(
      'Get match suggestions error:',
      error
    );

    return res.status(500).json({
      message: 'Failed to load match suggestions',
      error: error.message
    });
  }
};


// ----------------------------------------------------
// GET ONE MATCH
// GET /api/matches/:matchId
// ----------------------------------------------------

const getMatchById = async (req, res) => {
  try {
    const userId = req.user.user_id;
    const matchId = req.params.matchId;

    const [matches] = await pool.query(
      `
      SELECT
        mr.*,

        lost.item_name AS lost_item_name,
        lost.description AS lost_description,
        lost.location AS lost_location,

        found.item_name AS found_item_name,
        found.description AS found_description,
        found.location AS found_location,
        found.value_tier AS found_value_tier,
        found.status AS found_status

      FROM match_result mr

      JOIN item lost
        ON mr.lost_item_id = lost.item_id

      JOIN item found
        ON mr.found_item_id = found.item_id

      WHERE mr.match_id = ?
        AND (
          lost.reporter_id = ?
          OR ? IN (
            SELECT user_id
            FROM user
            WHERE user_id = ?
              AND role IN ('ADMIN', 'SUPER_ADMIN')
          )
        )
      `,
      [
        matchId,
        userId,
        userId,
        userId
      ]
    );

    if (matches.length === 0) {
      return res.status(404).json({
        message: 'Match not found'
      });
    }

    return res.status(200).json({
      match: matches[0]
    });

  } catch (error) {
    console.error(
      'Get match error:',
      error
    );

    return res.status(500).json({
      message: 'Failed to load match',
      error: error.message
    });
  }
};


module.exports = {
  getMyMatchSuggestions,
  getMatchById
};  */