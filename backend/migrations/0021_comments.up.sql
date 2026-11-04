-- Comments under spot updates, oldest first; id is the paging cursor.
-- status works like on updates and reviews: three distinct reports hide a
-- comment until an admin restores or deletes it.
CREATE TABLE comments (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  update_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  status ENUM('active','hidden') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_comments_update (update_id, id),
  KEY idx_comments_user (user_id),
  CONSTRAINT fk_comments_update FOREIGN KEY (update_id) REFERENCES spot_updates(id) ON DELETE CASCADE,
  CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE reports MODIFY target_type ENUM('spot','update','review','comment') NOT NULL;
