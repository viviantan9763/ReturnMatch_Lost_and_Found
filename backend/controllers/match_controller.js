const pool = require('../config/db');

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
};