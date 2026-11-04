-- Comments go back under updates: each one under its spot's newest update.
-- Comments on spots without any update have nowhere to go and are dropped
-- with their reports.
ALTER TABLE comments ADD COLUMN update_id BIGINT UNSIGNED NULL AFTER id;
UPDATE comments c SET c.update_id = (SELECT MAX(u.id) FROM spot_updates u WHERE u.spot_id = c.spot_id);
DELETE FROM reports WHERE target_type = 'comment' AND target_id IN (SELECT id FROM comments WHERE update_id IS NULL);
DELETE FROM comments WHERE update_id IS NULL;
ALTER TABLE comments MODIFY update_id BIGINT UNSIGNED NOT NULL;
ALTER TABLE comments
  ADD KEY idx_comments_update (update_id, id),
  ADD CONSTRAINT fk_comments_update FOREIGN KEY (update_id) REFERENCES spot_updates(id) ON DELETE CASCADE;
ALTER TABLE comments DROP FOREIGN KEY fk_comments_spot;
ALTER TABLE comments DROP INDEX idx_comments_spot, DROP COLUMN spot_id;
