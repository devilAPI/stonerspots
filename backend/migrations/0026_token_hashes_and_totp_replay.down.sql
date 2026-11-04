-- Hashes cannot be turned back into tokens: pending links stop working.
ALTER TABLE users
  DROP KEY uq_users_email_verify_hash,
  DROP KEY uq_users_password_reset_hash,
  DROP COLUMN totp_last_step,
  CHANGE email_verify_hash email_verify_token VARCHAR(255) NULL DEFAULT NULL,
  CHANGE password_reset_hash password_reset_token VARCHAR(255) NULL DEFAULT NULL;
UPDATE users SET email_verify_token = NULL, password_reset_token = NULL, password_reset_expires = NULL;
