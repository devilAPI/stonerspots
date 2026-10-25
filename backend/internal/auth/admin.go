package auth

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/totp"
)

// ErrNoSuchUser is returned by SetAdmin when no user has the given email.
var ErrNoSuchUser = errors.New("no user with that email")

// RequireAdmin must be used after Middleware. It reads is_admin from the
// database on every request (the JWT carries no role), so revoking admin
// takes effect immediately. A missing user row is 401, a non-admin 403.
// If the admin has 2FA enabled, the X-TOTP header must contain a valid code.
func RequireAdmin(db *sql.DB) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			id, ok := UserID(r.Context())
			if !ok {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			var admin bool
			var totpEnabled bool
			err := db.QueryRowContext(r.Context(), `SELECT is_admin, totp_enabled FROM users WHERE id = ?`, id).Scan(&admin, &totpEnabled)
			if errors.Is(err, sql.ErrNoRows) {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
				return
			}
			if err != nil {
				serverError(w)
				return
			}
			if !admin {
				httpx.Error(w, http.StatusForbidden, "forbidden", "admin access required")
				return
			}
			if totpEnabled {
				code := r.Header.Get("X-TOTP")
				if code == "" {
					httpx.Error(w, http.StatusUnauthorized, "totp_required", "2FA code required (X-TOTP header)")
					return
				}
				var secret string
				err := db.QueryRowContext(r.Context(), `SELECT totp_secret FROM users WHERE id = ?`, id).Scan(&secret)
				if err != nil || secret == "" {
					serverError(w)
					return
				}
				if !totp.Validate(secret, code) {
					httpx.Error(w, http.StatusUnauthorized, "totp_invalid", "invalid or expired 2FA code")
					return
				}
			}
			next.ServeHTTP(w, r)
		})
	}
}

// SetAdmin grants or revokes the admin flag of the user with the given
// email. It returns ErrNoSuchUser if the email is unknown.
func SetAdmin(ctx context.Context, db *sql.DB, email string, admin bool) error {
	email = normalizeEmail(email)
	var id uint64
	err := db.QueryRowContext(ctx, `SELECT id FROM users WHERE email = ?`, email).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNoSuchUser
	}
	if err != nil {
		return err
	}
	_, err = db.ExecContext(ctx, `UPDATE users SET is_admin = ? WHERE id = ?`, admin, id)
	return err
}
