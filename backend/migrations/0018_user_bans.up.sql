-- Banned users cannot log in or refresh their session; their content stays.
ALTER TABLE `users` ADD COLUMN `banned_at` DATETIME NULL DEFAULT NULL;
