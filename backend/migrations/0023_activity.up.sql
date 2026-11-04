-- Activity: what happened to a user's own content. user_id is the recipient,
-- actor_id the user who did it; the API never writes a row about yourself.
-- id is the paging cursor (newest first). read_at is set once the recipient
-- has seen the row.
CREATE TABLE activity (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  actor_id BIGINT UNSIGNED NOT NULL,
  kind ENUM('follow','comment','like','review') NOT NULL,
  spot_id BIGINT UNSIGNED NULL,
  update_id BIGINT UNSIGNED NULL,
  comment_id BIGINT UNSIGNED NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at TIMESTAMP NULL DEFAULT NULL,
  PRIMARY KEY (id),
  KEY idx_activity_user (user_id, id),
  KEY idx_activity_actor (actor_id),
  KEY idx_activity_spot (spot_id),
  KEY idx_activity_update (update_id),
  KEY idx_activity_comment (comment_id),
  CONSTRAINT fk_activity_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_activity_actor FOREIGN KEY (actor_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_activity_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE,
  CONSTRAINT fk_activity_update FOREIGN KEY (update_id) REFERENCES spot_updates(id) ON DELETE CASCADE,
  CONSTRAINT fk_activity_comment FOREIGN KEY (comment_id) REFERENCES comments(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
