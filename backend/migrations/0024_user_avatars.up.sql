-- Optional profile picture: the storage key of one square 384x384 JPEG in the
-- upload dir. It lives here and not in photos, so the cleanup of unattached
-- photos can never take it. The unique key lets GET /media/* check a key fast.
ALTER TABLE users
  ADD avatar_key VARCHAR(255) NULL,
  ADD UNIQUE KEY uq_users_avatar_key (avatar_key);
