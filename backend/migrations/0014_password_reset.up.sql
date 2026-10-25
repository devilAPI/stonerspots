ALTER TABLE `users`
  ADD COLUMN `password_reset_token` VARCHAR(255) DEFAULT NULL,
  ADD COLUMN `password_reset_expires` TIMESTAMP NULL DEFAULT NULL;