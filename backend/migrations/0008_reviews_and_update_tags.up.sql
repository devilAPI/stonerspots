CREATE TABLE spot_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spot_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  rating TINYINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  status ENUM('active','hidden') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reviews_spot_user (spot_id, user_id),
  KEY idx_reviews_spot_status (spot_id, status, id),
  KEY idx_reviews_user (user_id),
  CONSTRAINT fk_reviews_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE,
  CONSTRAINT fk_reviews_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE spot_updates
  ADD COLUMN tag ENUM('note','still_good','crowded','dirty','closed') NOT NULL DEFAULT 'note',
  ADD COLUMN edited_at TIMESTAMP NULL DEFAULT NULL;

ALTER TABLE reports MODIFY target_type ENUM('spot','update','review') NOT NULL;
