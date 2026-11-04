-- Comments belong to a spot (their own section on the spot page) instead of
-- hanging under an update. Each existing comment moves to its update's spot;
-- deleting an update no longer takes comments with it.
ALTER TABLE comments ADD COLUMN spot_id BIGINT UNSIGNED NULL AFTER id;
UPDATE comments c JOIN spot_updates u ON u.id = c.update_id SET c.spot_id = u.spot_id;
ALTER TABLE comments MODIFY spot_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE comments
  ADD KEY idx_comments_spot (spot_id, id),
  ADD CONSTRAINT fk_comments_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE;
ALTER TABLE comments DROP FOREIGN KEY fk_comments_update;
ALTER TABLE comments DROP INDEX idx_comments_update, DROP COLUMN update_id;
