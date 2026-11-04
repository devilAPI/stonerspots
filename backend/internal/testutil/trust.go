package testutil

import (
	"database/sql"
	"testing"
)

// NewTrustedUser inserts a user whose reports count towards auto-hiding
// (see engagement/repo.go): eight days old, email verified, with one active
// spot of their own (at 0,0, far from the test spots).
func NewTrustedUser(t *testing.T, db *sql.DB) uint64 {
	t.Helper()
	id := NewUser(t, db)
	if _, err := db.Exec(`UPDATE users SET created_at = NOW() - INTERVAL 8 DAY, email_verified = 1 WHERE id = ?`, id); err != nil {
		t.Fatalf("testutil: age user: %v", err)
	}
	if _, err := db.Exec(`INSERT INTO spots (user_id, title, description, location)
		VALUES (?, 'Trusted contribution', '', ST_GeomFromText('POINT(0 0)'))`, id); err != nil {
		t.Fatalf("testutil: contribution: %v", err)
	}
	return id
}
