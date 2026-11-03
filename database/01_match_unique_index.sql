-- Run once after checking duplicate pairs; back up your database first.
SELECT lost_item_id,found_item_id,COUNT(*) AS duplicates
FROM match_result GROUP BY lost_item_id,found_item_id HAVING COUNT(*)>1;
-- If duplicates are returned, resolve them manually before running ALTER TABLE.
ALTER TABLE match_result
 ADD UNIQUE KEY uq_match_lost_found (lost_item_id,found_item_id);