ALTER TABLE `photos`
  ADD COLUMN `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending' AFTER `height`,
  ADD INDEX `idx_photos_status` (`status`);