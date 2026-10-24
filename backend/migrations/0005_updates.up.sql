CREATE TABLE spot_updates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  spot_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  body TEXT NOT NULL,
  status ENUM('active','hidden') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_updates_created (created_at, id),
  KEY idx_updates_spot (spot_id),
  KEY idx_updates_user (user_id),
  CONSTRAINT fk_updates_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE,
  CONSTRAINT fk_updates_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE photos
  ADD CONSTRAINT fk_photos_update FOREIGN KEY (update_id) REFERENCES spot_updates(id) ON DELETE SET NULL;
