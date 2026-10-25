-- Stonerspots database layout (MariaDB 11.4), for reference and for setting up
-- a database by hand:  mariadb -u root -p stonerspots < schema.example.sql
--
-- GENERATED from migrations/ - do not edit. The migrations are the source of
-- truth and the API applies them on start; regenerate this file with
--   UPDATE_SCHEMA=1 go test ./internal/server -run TestSchemaFile
-- The schema_migrations row marks every migration as applied, so the API
-- does not try to run them again on a database created from this file.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `photos`;
CREATE TABLE `photos` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `key` varchar(255) NOT NULL,
  `thumb_key` varchar(255) NOT NULL,
  `width` int(11) NOT NULL,
  `height` int(11) NOT NULL,
  `update_id` bigint(20) unsigned DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_photos_user` (`user_id`),
  KEY `idx_photos_update` (`update_id`),
  CONSTRAINT `fk_photos_update` FOREIGN KEY (`update_id`) REFERENCES `spot_updates` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_photos_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `refresh_tokens`;
CREATE TABLE `refresh_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `token_hash` char(64) NOT NULL,
  `family_id` char(36) NOT NULL,
  `expires_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `revoked_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_refresh_token_hash` (`token_hash`),
  KEY `idx_refresh_family` (`family_id`),
  KEY `idx_refresh_user` (`user_id`),
  CONSTRAINT `fk_refresh_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `reports`;
CREATE TABLE `reports` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `target_type` enum('spot','update','review') NOT NULL,
  `target_id` bigint(20) unsigned NOT NULL,
  `reason` varchar(500) NOT NULL DEFAULT '',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_reports_once` (`user_id`,`target_type`,`target_id`),
  KEY `idx_reports_target` (`target_type`,`target_id`),
  CONSTRAINT `fk_reports_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `schema_migrations`;
CREATE TABLE `schema_migrations` (
  `version` bigint(20) NOT NULL,
  `dirty` tinyint(1) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `spots`;
CREATE TABLE `spots` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `title` varchar(80) NOT NULL,
  `description` text NOT NULL,
  `location` point NOT NULL,
  `like_count` int(11) NOT NULL DEFAULT 0,
  `status` enum('active','hidden') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `locked` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  SPATIAL KEY `idx_spots_location` (`location`),
  KEY `idx_spots_user` (`user_id`),
  CONSTRAINT `fk_spots_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `spot_likes`;
CREATE TABLE `spot_likes` (
  `user_id` bigint(20) unsigned NOT NULL,
  `spot_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`,`spot_id`),
  KEY `idx_likes_spot` (`spot_id`),
  CONSTRAINT `fk_likes_spot` FOREIGN KEY (`spot_id`) REFERENCES `spots` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_likes_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `spot_reviews`;
CREATE TABLE `spot_reviews` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `spot_id` bigint(20) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `rating` tinyint(3) unsigned NOT NULL,
  `body` text NOT NULL,
  `status` enum('active','hidden') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_reviews_spot_user` (`spot_id`,`user_id`),
  KEY `idx_reviews_spot_status` (`spot_id`,`status`,`id`),
  KEY `idx_reviews_user` (`user_id`),
  CONSTRAINT `fk_reviews_spot` FOREIGN KEY (`spot_id`) REFERENCES `spots` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reviews_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `spot_tags`;
CREATE TABLE `spot_tags` (
  `spot_id` bigint(20) unsigned NOT NULL,
  `tag` varchar(16) NOT NULL,
  PRIMARY KEY (`spot_id`,`tag`),
  KEY `idx_spot_tags_tag` (`tag`,`spot_id`),
  CONSTRAINT `fk_spot_tags_spot` FOREIGN KEY (`spot_id`) REFERENCES `spots` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_spot_tags_tag` FOREIGN KEY (`tag`) REFERENCES `tags` (`tag`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `spot_updates`;
CREATE TABLE `spot_updates` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `spot_id` bigint(20) unsigned NOT NULL,
  `user_id` bigint(20) unsigned NOT NULL,
  `body` text NOT NULL,
  `status` enum('active','hidden') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `tag` enum('note','still_good','crowded','dirty','closed') NOT NULL DEFAULT 'note',
  `edited_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_updates_created` (`created_at`,`id`),
  KEY `idx_updates_spot` (`spot_id`),
  KEY `idx_updates_user` (`user_id`),
  CONSTRAINT `fk_updates_spot` FOREIGN KEY (`spot_id`) REFERENCES `spots` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_updates_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `tags`;
CREATE TABLE `tags` (
  `tag` varchar(16) NOT NULL,
  `name_de` varchar(40) NOT NULL,
  `name_en` varchar(40) NOT NULL,
  `icon` varchar(32) NOT NULL,
  `sort` int(11) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `email` varchar(255) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `display_name` varchar(80) NOT NULL,
  `adult_confirmed_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_admin` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `schema_migrations` (`version`, `dirty`) VALUES (11, 0);

INSERT INTO `tags` (`tag`, `name_de`, `name_en`, `icon`, `sort`) VALUES
  ('roof', 'Überdacht', 'Roof', 'roof', 10),
  ('seating', 'Sitzgelegenheit', 'Seating', 'seating', 20),
  ('view', 'Aussicht', 'View', 'view', 30),
  ('quiet', 'Ruhig', 'Quiet', 'quiet', 40),
  ('shade', 'Schatten', 'Shade', 'shade', 50),
  ('water', 'Wasser in der Nähe', 'Water nearby', 'water', 60),
  ('lit', 'Beleuchtet', 'Lit', 'lit', 70);

SET FOREIGN_KEY_CHECKS = 1;
