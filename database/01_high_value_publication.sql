-- ReturnMatch Phase 3A - Run ONCE after backing up your database.
-- MEDIUM reports: automatic publication.
-- HIGH reports: require Admin review before public listing / AI matching.
-- item.status remains the original item lifecycle status.

ALTER TABLE item
  MODIFY COLUMN model_info VARCHAR(100) NULL,
  ADD COLUMN publication_status
    ENUM('PENDING_REVIEW','PUBLISHED','REJECTED')
    NOT NULL DEFAULT 'PENDING_REVIEW'
    AFTER status,
  ADD COLUMN publication_reviewed_by INT UNSIGNED NULL
    AFTER publication_status,
  ADD COLUMN publication_reviewed_at DATETIME NULL
    AFTER publication_reviewed_by,
  ADD COLUMN publication_review_note VARCHAR(500) NULL
    AFTER publication_reviewed_at;

-- Preserve old MEDIUM reports as publicly visible.
-- HIGH ACTIVE reports stay pending; historical non-ACTIVE reports stay accessible
-- to their owners and admins, and retain their publication state if appropriate.
UPDATE item
SET publication_status = 'PUBLISHED'
WHERE value_tier = 'MEDIUM' OR status <> 'ACTIVE';

CREATE INDEX idx_item_publication_match
ON item (publication_status, item_type, category_id, status);

-- Check the results:
SELECT item_id, item_name, item_type, value_tier,
       status, publication_status
FROM item
ORDER BY item_id;

-- IMPORTANT: Check audit_log.action_type before testing Admin Approve/Reject:
SHOW COLUMNS FROM audit_log LIKE 'action_type';
