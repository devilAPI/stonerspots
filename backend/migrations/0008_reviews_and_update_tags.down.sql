DELETE FROM reports WHERE target_type = 'review';
ALTER TABLE reports MODIFY target_type ENUM('spot','update') NOT NULL;
ALTER TABLE spot_updates DROP COLUMN edited_at, DROP COLUMN tag;
DROP TABLE IF EXISTS spot_reviews;
