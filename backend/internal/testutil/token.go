package testutil

import (
	"database/sql"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"stonerspots/backend/internal/auth"
)

// JWTSecret is the secret tests must put into config.Config.JWTSecret
// (as []byte(testutil.JWTSecret)) so that Token values validate.
const JWTSecret = "test-jwt-secret"

var userSeq atomic.Uint64

// Token returns a valid access token for userID, signed with JWTSecret.
func Token(t *testing.T, userID uint64) string {
	t.Helper()
	tok, err := auth.IssueAccess([]byte(JWTSecret), userID, time.Hour)
	if err != nil {
		t.Fatalf("testutil: issue token: %v", err)
	}
	return tok
}

// NewUser inserts a user row (unique email, dummy password hash) and returns its id.
func NewUser(t *testing.T, db *sql.DB) uint64 {
	t.Helper()
	n := userSeq.Add(1)
	res, err := db.Exec(`INSERT INTO users (email, password_hash, display_name) VALUES (?, 'x', ?)`,
		fmt.Sprintf("user%d-%d@example.test", n, time.Now().UnixNano()), fmt.Sprintf("User %d", n))
	if err != nil {
		t.Fatalf("testutil: insert user: %v", err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}
