package main

import (
	"bytes"
	"context"
	"strings"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestRun(t *testing.T) {
	db := testutil.NewDB(t)
	id := testutil.NewUser(t, db)
	var email string
	_ = db.QueryRow(`SELECT email FROM users WHERE id=?`, id).Scan(&email)
	var out, errOut bytes.Buffer

	if code := run(context.Background(), db, email, false, &out, &errOut); code != 0 || !strings.Contains(out.String(), "granted") {
		t.Fatalf("grant: %d %q %q", code, out.String(), errOut.String())
	}
	var a bool
	_ = db.QueryRow(`SELECT is_admin FROM users WHERE id=?`, id).Scan(&a)
	if !a {
		t.Fatal("not admin")
	}
	out.Reset()
	if code := run(context.Background(), db, email, true, &out, &errOut); code != 0 || !strings.Contains(out.String(), "revoked") {
		t.Fatalf("revoke: %d %q", code, out.String())
	}
	_ = db.QueryRow(`SELECT is_admin FROM users WHERE id=?`, id).Scan(&a)
	if a {
		t.Fatal("still admin")
	}
	errOut.Reset()
	if code := run(context.Background(), db, "nobody@example.com", false, &out, &errOut); code == 0 || !strings.Contains(errOut.String(), "no user") {
		t.Fatalf("unknown: %d %q", code, errOut.String())
	}
}
