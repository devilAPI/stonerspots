package auth_test

import (
	"bytes"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

func TestBannedUserCannotLogInOrRefresh(t *testing.T) {
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) {
		auth.MountForTest(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}})
	})
	reg := register(t, r, "banned@example.com")
	if _, err := db.Exec(`UPDATE users SET banned_at = UTC_TIMESTAMP() WHERE id = ?`, reg.User.ID); err != nil {
		t.Fatal(err)
	}

	rec := do(t, r, "POST", "/auth/login", "", map[string]any{"email": "banned@example.com", "password": "correct-horse-1"})
	if rec.Code != 403 || !bytes.Contains(rec.Body.Bytes(), []byte("account_banned")) {
		t.Fatalf("login: %d %s", rec.Code, rec.Body)
	}
	// a wrong password does not learn about the ban
	rec = do(t, r, "POST", "/auth/login", "", map[string]any{"email": "banned@example.com", "password": "wrong-password-1"})
	if rec.Code != 401 {
		t.Fatalf("wrong password: %d %s", rec.Code, rec.Body)
	}
	// a session from before the ban ends at its next refresh
	if rec := refresh(t, r, reg.RefreshToken); rec.Code != 401 {
		t.Fatalf("refresh: %d %s", rec.Code, rec.Body)
	}

	if _, err := db.Exec(`UPDATE users SET banned_at = NULL WHERE id = ?`, reg.User.ID); err != nil {
		t.Fatal(err)
	}
	rec = do(t, r, "POST", "/auth/login", "", map[string]any{"email": "banned@example.com", "password": "correct-horse-1"})
	if rec.Code != 200 {
		t.Fatalf("after unban: %d %s", rec.Code, rec.Body)
	}
}
