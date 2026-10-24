package auth_test

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

func TestIsAdminInResponsesAndNotSettable(t *testing.T) {
	d := app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.Mount(r, d) })

	rec := do(t, r, "POST", "/auth/register", "", map[string]any{
		"email": "a@example.com", "password": "correct-horse-1", "display_name": "A", "adult": true, "is_admin": true,
	})
	if rec.Code != 201 {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
	type resp struct {
		AccessToken string `json:"access_token"`
		User        struct {
			IsAdmin *bool `json:"is_admin"`
		} `json:"user"`
	}
	reg := decode[resp](t, rec)
	if reg.User.IsAdmin == nil || *reg.User.IsAdmin {
		t.Fatalf("register is_admin must be present and false: %s", rec.Body)
	}
	var stored bool
	if err := d.DB.QueryRow(`SELECT is_admin FROM users WHERE email='a@example.com'`).Scan(&stored); err != nil || stored {
		t.Fatalf("stored admin = %v err %v", stored, err)
	}

	if _, err := d.DB.Exec(`UPDATE users SET is_admin=1 WHERE email='a@example.com'`); err != nil {
		t.Fatal(err)
	}
	rec = do(t, r, "POST", "/auth/login", "", map[string]any{"email": "a@example.com", "password": "correct-horse-1", "is_admin": false})
	login := decode[resp](t, rec)
	if login.User.IsAdmin == nil || !*login.User.IsAdmin {
		t.Fatalf("login is_admin: %s", rec.Body)
	}
	rec = do(t, r, "GET", "/me", login.AccessToken, nil)
	me := decode[struct {
		IsAdmin *bool `json:"is_admin"`
	}](t, rec)
	if me.IsAdmin == nil || !*me.IsAdmin {
		t.Fatalf("/me is_admin: %s", rec.Body)
	}
	rec = do(t, r, "PUT", "/me/password", login.AccessToken, map[string]any{
		"current_password": "correct-horse-1", "new_password": "another-horse-22",
	})
	pw := decode[resp](t, rec)
	if pw.User.IsAdmin == nil || !*pw.User.IsAdmin {
		t.Fatalf("password is_admin: %s", rec.Body)
	}
}

func TestRequireAdmin(t *testing.T) {
	db := testutil.NewDB(t)
	secret := []byte(testutil.JWTSecret)
	h := auth.Middleware(secret)(auth.RequireAdmin(db)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(204)
	})))
	call := func(tok string) int {
		req := httptest.NewRequest("GET", "/", nil)
		if tok != "" {
			req.Header.Set("Authorization", "Bearer "+tok)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, req)
		return w.Code
	}
	u := testutil.NewUser(t, db)
	tok := testutil.Token(t, u)
	if c := call(""); c != 401 {
		t.Fatalf("anon %d", c)
	}
	if c := call(tok); c != 403 {
		t.Fatalf("user %d", c)
	}
	db.Exec(`UPDATE users SET is_admin=1 WHERE id=?`, u)
	if c := call(tok); c != 204 {
		t.Fatalf("admin %d", c)
	}
	db.Exec(`UPDATE users SET is_admin=0 WHERE id=?`, u)
	if c := call(tok); c != 403 {
		t.Fatalf("revoked %d", c)
	}
	db.Exec(`DELETE FROM users WHERE id=?`, u)
	if c := call(tok); c != 401 {
		t.Fatalf("missing user %d", c)
	}
}

func TestSetAdmin(t *testing.T) {
	db := testutil.NewDB(t)
	u := testutil.NewUser(t, db)
	var email string
	db.QueryRow(`SELECT email FROM users WHERE id=?`, u).Scan(&email)
	ctx := context.Background()
	if err := auth.SetAdmin(ctx, db, " "+email+" ", true); err != nil {
		t.Fatal(err)
	}
	var a bool
	db.QueryRow(`SELECT is_admin FROM users WHERE id=?`, u).Scan(&a)
	if !a {
		t.Fatal("not promoted")
	}
	if err := auth.SetAdmin(ctx, db, email, true); err != nil {
		t.Fatalf("idempotent promote: %v", err)
	}
	if err := auth.SetAdmin(ctx, db, email, false); err != nil {
		t.Fatal(err)
	}
	db.QueryRow(`SELECT is_admin FROM users WHERE id=?`, u).Scan(&a)
	if a {
		t.Fatal("not revoked")
	}
	if err := auth.SetAdmin(ctx, db, "nobody@example.com", true); !errors.Is(err, auth.ErrNoSuchUser) {
		t.Fatalf("want ErrNoSuchUser, got %v", err)
	}
}
