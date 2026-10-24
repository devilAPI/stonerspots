CREATE TABLE spots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(80) NOT NULL,
  description TEXT NOT NULL,
  category ENUM('bench','river','lake','viewpoint','forest','park','other') NOT NULL,
  location POINT NOT NULL,
  like_count INT NOT NULL DEFAULT 0,
  status ENUM('active','hidden') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  SPATIAL INDEX idx_spots_location (location),
  KEY idx_spots_user (user_id),
  KEY idx_spots_category (category),
  CONSTRAINT fk_spots_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
