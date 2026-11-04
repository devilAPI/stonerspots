-- Email verification and password reset tokens are stored as the hex SHA-256
-- of the token that was mailed (like refresh tokens), so a leaked database
-- holds no usable reset links. The unique keys make the lookup by hash an
-- index read instead of a scan of users. Pending tokens are hashed in place,
-- so links that were already sent keep working; '' (written by registrations
-- while mail was off) means "none".
UPDATE users SET email_verify_token = NULL, email_verify_expires = NULL WHERE email_verify_token = '';
UPDATE users SET password_reset_token = NULL, password_reset_expires = NULL WHERE password_reset_token = '';
UPDATE users SET email_verify_token = SHA2(email_verify_token, 256) WHERE email_verify_token IS NOT NULL;
UPDATE users SET password_reset_token = SHA2(password_reset_token, 256) WHERE password_reset_token IS NOT NULL;
-- totp_last_step is the last accepted 2FA time step (unix time / 30): each
-- code is accepted once, so a code seen by someone else cannot be replayed.
ALTER TABLE users
  CHANGE email_verify_token email_verify_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL,
  CHANGE password_reset_token password_reset_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL DEFAULT NULL,
  ADD totp_last_step BIGINT NULL DEFAULT NULL,
  ADD UNIQUE KEY uq_users_email_verify_hash (email_verify_hash),
  ADD UNIQUE KEY uq_users_password_reset_hash (password_reset_hash);
