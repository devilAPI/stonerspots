ALTER TABLE `photos`
  MODIFY COLUMN `status` ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending';
