-- Display names double as login names, so they must be unique (the
-- collation makes this case-insensitive). Existing duplicates keep the
-- oldest account's name; later ones get their id appended.
UPDATE `users` SET `display_name` = TRIM(`display_name`);
UPDATE `users` SET `display_name` = CONCAT('user ', `id`) WHERE `display_name` = '';
UPDATE `users` u
  JOIN `users` o ON o.`display_name` = u.`display_name` AND o.`id` < u.`id`
  SET u.`display_name` = CONCAT(LEFT(u.`display_name`, 70), ' ', u.`id`);
ALTER TABLE `users` ADD UNIQUE KEY `uq_users_display_name` (`display_name`);
