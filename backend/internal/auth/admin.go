package auth

import (
	"context"
	"database/sql"
	"errors"
)

// ErrNoSuchUser is returned by SetAdmin when no user has the given email.
var ErrNoSuchUser = errors.New("no user with that email")

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
