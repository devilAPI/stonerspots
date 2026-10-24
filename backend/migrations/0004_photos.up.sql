-- update_id is NULL while a photo is unattached; the FK to spot_updates is added in 0005.
CREATE TABLE photos (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  `key` VARCHAR(255) NOT NULL,
  thumb_key VARCHAR(255) NOT NULL,
  width INT NOT NULL,
  height INT NOT NULL,
  update_id BIGINT UNSIGNED NULL DEFAULT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_photos_user (user_id),
  KEY idx_photos_update (update_id),
  CONSTRAINT fk_photos_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
