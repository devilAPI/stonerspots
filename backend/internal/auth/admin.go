package auth

import (
	"context"
	"database/sql"
	"errors"
	"net/http"

	"stonerspots/backend/internal/httpx"
)

// ErrNoSuchUser is returned by SetAdmin when no user has the given email.
var ErrNoSuchUser = errors.New("no user with that email")

// RequireAdmin must be used after Middleware. It reads is_admin from the
// database on every request (the JWT carries no role), so revoking admin
// takes effect immediately. A missing user row is 401, a non-admin 403.
func RequireAdmin(db *sql.DB) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			id, ok := UserID(r.Context())
			if !ok {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			var admin bool
			err := db.QueryRowContext(r.Context(), `SELECT is_admin FROM users WHERE id = ?`, id).Scan(&admin)
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
