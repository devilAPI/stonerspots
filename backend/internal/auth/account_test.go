package auth_test

import (
	"database/sql"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

const pw = "correct-horse-1"

type env struct {
	h   http.Handler
	db  *sql.DB
	dir string
}

func newEnv(t *testing.T) env {
	t.Helper()
	d := testutil.NewDB(t)
	dir := t.TempDir()
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: dir, PublicBaseURL: "http://test"}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.Mount(r, app.Deps{DB: d, Cfg: cfg}) })
	return env{h: r, db: d, dir: dir}
}

func count(t *testing.T, db *sql.DB, q string, args ...any) int {
	t.Helper()
	var n int
	if err := db.QueryRow(q, args...).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestChangePasswordWrongCurrent403(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	rec := do(t, e.h, "PUT", "/me/password", u.AccessToken, map[string]any{"current_password": "nope-nope-nope", "new_password": "brand-new-password"})
	if rec.Code != 403 || !strings.Contains(rec.Body.String(), "wrong_password") {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	if rec := do(t, e.h, "POST", "/auth/login", "", map[string]any{"email": "a@example.com", "password": pw}); rec.Code != 200 {
		t.Fatalf("old password should still work: %d", rec.Code)
	}
	if rec := refresh(t, e.h, u.RefreshToken); rec.Code != 200 {
		t.Fatalf("refresh token should be untouched: %d", rec.Code)
	}
}

func TestChangePasswordRejectsBadNew(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	for name, np := range map[string]string{
		"short": "short", "toolong": strings.Repeat("x", 73), "same": pw,
	} {
		rec := do(t, e.h, "PUT", "/me/password", u.AccessToken, map[string]any{"current_password": pw, "new_password": np})
		if rec.Code != 400 || !strings.Contains(rec.Body.String(), "invalid_password") {
			t.Errorf("%s: got %d %s", name, rec.Code, rec.Body)
		}
	}
}

func TestChangePasswordSuccessRotatesSessions(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	other := do(t, e.h, "POST", "/auth/login", "", map[string]any{"email": "a@example.com", "password": pw})
	otherDevice := decode[authResp](t, other)

	rec := do(t, e.h, "PUT", "/me/password", u.AccessToken, map[string]any{"current_password": pw, "new_password": "brand-new-password"})
	if rec.Code != 200 {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	n := decode[authResp](t, rec)
	if n.AccessToken == "" || n.RefreshToken == "" || n.User.ID != u.User.ID || n.User.Email != "a@example.com" {
		t.Fatalf("bad body: %+v", n)
	}
	if refresh(t, e.h, u.RefreshToken).Code != 401 || refresh(t, e.h, otherDevice.RefreshToken).Code != 401 {
		t.Fatal("old refresh tokens must be rejected")
	}
	if rec := refresh(t, e.h, n.RefreshToken); rec.Code != 200 {
		t.Fatalf("new refresh token should work: %d", rec.Code)
	}
	if rec := do(t, e.h, "POST", "/auth/login", "", map[string]any{"email": "a@example.com", "password": pw}); rec.Code != 401 {
		t.Fatalf("old password login: %d", rec.Code)
	}
	if rec := do(t, e.h, "POST", "/auth/login", "", map[string]any{"email": "a@example.com", "password": "brand-new-password"}); rec.Code != 200 {
		t.Fatalf("new password login: %d", rec.Code)
	}
}

func TestAccountEndpointsRequireAuth(t *testing.T) {
	e := newEnv(t)
	if rec := do(t, e.h, "PUT", "/me/password", "", map[string]any{"current_password": pw, "new_password": "brand-new-password"}); rec.Code != 401 {
		t.Fatalf("password: %d", rec.Code)
	}
	if rec := do(t, e.h, "POST", "/me/delete", "", map[string]any{"password": pw}); rec.Code != 401 {
		t.Fatalf("delete: %d", rec.Code)
	}
}

func TestDeleteWrongPassword403(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	rec := do(t, e.h, "POST", "/me/delete", u.AccessToken, map[string]any{"password": "wrong-wrong-wrong"})
	if rec.Code != 403 || !strings.Contains(rec.Body.String(), "wrong_password") {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	if do(t, e.h, "GET", "/me", u.AccessToken, nil).Code != 200 {
		t.Fatal("user must still exist")
	}
}

func TestDeleteRemovesDataAndFiles(t *testing.T) {
	e := newEnv(t)
	u := register(t, e.h, "a@example.com")
	o := register(t, e.h, "b@example.com")
	mkfile := func(name string) string {
		p := filepath.Join(e.dir, name)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
		return p
	}
	mine, mineT := mkfile("2026/a.jpg"), mkfile("2026/a_t.jpg")
	theirs, theirsT := mkfile("2026/b.jpg"), mkfile("2026/b_t.jpg")
	outsideName := "outside-" + filepath.Base(e.dir)
	outside := filepath.Join(filepath.Dir(e.dir), outsideName)
	if err := os.WriteFile(outside, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	defer os.Remove(outside)

	ins := func(q string, args ...any) int64 {
		res, err := e.db.Exec(q, args...)
		if err != nil {
			t.Fatal(err)
		}
		id, _ := res.LastInsertId()
		return id
	}
	spot := func(uid uint64) int64 {
		return ins("INSERT INTO spots (user_id, title, description, location) VALUES (?, 't', 'd', ST_GeomFromText('POINT(1 1)'))", uid)
	}
	sMine, sTheirs := spot(u.User.ID), spot(o.User.ID)
	upd := func(s int64, uid uint64) int64 {
		return ins("INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?, ?, 'hi')", s, uid)
	}
	upd(sMine, u.User.ID)
	upd(sTheirs, u.User.ID) // my update on their spot
	uTheirs := upd(sTheirs, o.User.ID)
	ins("INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)", u.User.ID, sTheirs)
	ins("INSERT INTO spot_likes (user_id, spot_id) VALUES (?, ?)", o.User.ID, sTheirs)
	ins("INSERT INTO reports (user_id, target_type, target_id) VALUES (?, 'spot', ?)", u.User.ID, sTheirs)
	photo := func(uid uint64, k, tk string, upd any) {
		ins("INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, ?, ?, 1, 1, ?)", uid, k, tk, upd)
	}
	photo(u.User.ID, "2026/a.jpg", "2026/a_t.jpg", nil)
	photo(u.User.ID, "../"+outsideName, "/etc/passwd", nil)
	photo(u.User.ID, "2026/missing.jpg", "2026/missing_t.jpg", nil)
	photo(o.User.ID, "2026/b.jpg", "2026/b_t.jpg", uTheirs)

	rec := do(t, e.h, "POST", "/me/delete", u.AccessToken, map[string]any{"password": pw})
	if rec.Code != 204 || rec.Body.Len() != 0 {
		t.Fatalf("got %d %q", rec.Code, rec.Body)
	}
	for _, tbl := range []string{"spots", "spot_updates", "spot_likes", "reports", "photos", "refresh_tokens"} {
		if n := count(t, e.db, "SELECT COUNT(*) FROM "+tbl+" WHERE user_id = ?", u.User.ID); n != 0 {
			t.Errorf("%s still has %d rows", tbl, n)
		}
	}
	if count(t, e.db, "SELECT COUNT(*) FROM users WHERE id = ?", u.User.ID) != 0 {
		t.Error("user still exists")
	}
	// other user's data intact (their spot, update, like, photo)
	if count(t, e.db, "SELECT COUNT(*) FROM spots WHERE id = ?", sTheirs) != 1 ||
		count(t, e.db, "SELECT COUNT(*) FROM spot_updates WHERE user_id = ?", o.User.ID) != 1 ||
		count(t, e.db, "SELECT COUNT(*) FROM spot_likes WHERE user_id = ?", o.User.ID) != 1 ||
		count(t, e.db, "SELECT COUNT(*) FROM photos WHERE user_id = ?", o.User.ID) != 1 {
		t.Error("other user's data was damaged")
	}
	for _, p := range []string{mine, mineT} {
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Errorf("%s should be removed", p)
		}
	}
	for _, p := range []string{theirs, theirsT, outside} {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("%s must remain: %v", p, err)
		}
	}
	// deleted user's token is dead, and the email is reusable
	if rec := do(t, e.h, "GET", "/me", u.AccessToken, nil); rec.Code != 401 || !strings.Contains(rec.Body.String(), "unauthorized") {
		t.Fatalf("/me after delete: %d %s", rec.Code, rec.Body)
	}
	if rec := do(t, e.h, "POST", "/me/delete", u.AccessToken, map[string]any{"password": pw}); rec.Code != 401 {
		t.Fatalf("second delete: %d", rec.Code)
	}
	if rec := do(t, e.h, "PUT", "/me/password", u.AccessToken, map[string]any{"current_password": pw, "new_password": "brand-new-password"}); rec.Code != 401 {
		t.Fatalf("password after delete: %d", rec.Code)
	}
	register(t, e.h, "a@example.com")
}
