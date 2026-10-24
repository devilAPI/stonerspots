CREATE TABLE spot_tags (
  spot_id BIGINT UNSIGNED NOT NULL,
  tag VARCHAR(16) NOT NULL,
  PRIMARY KEY (spot_id, tag),
  KEY idx_spot_tags_tag (tag, spot_id),
  CONSTRAINT fk_spot_tags_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
