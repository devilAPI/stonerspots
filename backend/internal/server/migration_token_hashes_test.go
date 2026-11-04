package server_test

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"testing"

	"stonerspots/backend/internal/testutil"
)

// 0026 hashes pending verification and reset tokens in place (so links
// already mailed keep working) and drops the empty strings that
// registrations wrote while mail was off.
func TestTokenHashMigration(t *testing.T) {
	d, dsn := testutil.NewEmptyDB(t)
	migrateTo(t, dsn, 24)
	for _, u := range []struct{ email, verify, reset string }{
		{"a@x.de", "verify-token-a", "reset-token-a"},
		{"b@x.de", "", ""},
		{"c@x.de", "verify-token-c", ""},
	} {
		if _, err := d.Exec(`INSERT INTO users (email, password_hash, display_name, email_verify_token, password_reset_token)
			VALUES (?, 'x', ?, ?, NULLIF(?, ''))`, u.email, u.email, u.verify, u.reset); err != nil {
			t.Fatal(err)
		}
	}
	migrateTo(t, dsn, 26)
	sum := func(s string) string { h := sha256.Sum256([]byte(s)); return hex.EncodeToString(h[:]) }
	get := func(email string) (v, r sql.NullString) {
		if err := d.QueryRow(`SELECT email_verify_hash, password_reset_hash FROM users WHERE email = ?`, email).Scan(&v, &r); err != nil {
			t.Fatal(err)
		}
		return
	}
	if v, r := get("a@x.de"); v.String != sum("verify-token-a") || r.String != sum("reset-token-a") {
		t.Fatalf("a: %v %v", v, r)
	}
	if v, r := get("b@x.de"); v.Valid || r.Valid {
		t.Fatalf("b: %v %v", v, r)
	}
	if v, r := get("c@x.de"); v.String != sum("verify-token-c") || r.Valid {
		t.Fatalf("c: %v %v", v, r)
	}
	var step sql.NullInt64
	if err := d.QueryRow(`SELECT totp_last_step FROM users WHERE email = 'a@x.de'`).Scan(&step); err != nil || step.Valid {
		t.Fatalf("totp_last_step %v %v", step, err)
	}
}
