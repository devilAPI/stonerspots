-- Saved spots: private lists owned by one user. Every user has one default
-- list (Favourites), created on first use; the app shows its name translated.
-- The name collation compares case and accents loosely, like other names here,
-- but unlike utf8mb4_unicode_ci it tells emoji apart.
-- default_slot is NULL for normal lists, so the unique key allows just one
-- default list per user and any number of others.
CREATE TABLE spot_lists (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(60) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  is_default TINYINT(1) NOT NULL DEFAULT 0,
  default_slot TINYINT(1) AS (IF(is_default, 1, NULL)) PERSISTENT,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_spot_lists_name (user_id, name),
  UNIQUE KEY uq_spot_lists_default (user_id, default_slot),
  CONSTRAINT fk_spot_lists_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- id orders a list, newest save first, and is its paging cursor.
CREATE TABLE spot_list_items (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  list_id BIGINT UNSIGNED NOT NULL,
  spot_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_spot_list_items (list_id, spot_id),
  KEY idx_spot_list_items_page (list_id, id),
  KEY idx_spot_list_items_spot (spot_id),
  CONSTRAINT fk_spot_list_items_list FOREIGN KEY (list_id) REFERENCES spot_lists(id) ON DELETE CASCADE,
  CONSTRAINT fk_spot_list_items_spot FOREIGN KEY (spot_id) REFERENCES spots(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
