package auth_test

import (
	"bytes"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

func TestLoginWithNameOrEmail(t *testing.T) {
	h := newRouter(t)
	rec := do(t, h, "POST", "/auth/register", "", map[string]any{
		"email": "max@example.com", "password": "correct-horse-1", "display_name": "  Max Mustermann ", "adult": true})
	if rec.Code != 201 {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
	if u := decode[authResp](t, rec).User; u.DisplayName != "Max Mustermann" {
		t.Fatalf("name not trimmed: %q", u.DisplayName)
	}
	for _, body := range []map[string]any{
		{"login": "Max Mustermann", "password": "correct-horse-1"},
		{"login": " max mustermann ", "password": "correct-horse-1"}, // any case
		{"login": "MAX@example.com", "password": "correct-horse-1"},
		{"email": "max@example.com", "password": "correct-horse-1"}, // older apps
	} {
		if rec := do(t, h, "POST", "/auth/login", "", body); rec.Code != 200 {
			t.Fatalf("%v: %d %s", body, rec.Code, rec.Body)
		}
	}
	for _, body := range []map[string]any{
		{"login": "Max Mustermann", "password": "wrong-password-1"},
		{"login": "Nobody", "password": "correct-horse-1"},
	} {
		if rec := do(t, h, "POST", "/auth/login", "", body); rec.Code != 401 {
			t.Fatalf("%v: %d %s", body, rec.Code, rec.Body)
		}
	}
}

func TestDisplayNamesAreUnique(t *testing.T) {
	h := newRouter(t)
	reg := func(email, name string) (int, string) {
		rec := do(t, h, "POST", "/auth/register", "", map[string]any{
			"email": email, "password": "correct-horse-1", "display_name": name, "adult": true})
		return rec.Code, rec.Body.String()
	}
	if c, b := reg("a@example.com", "Hanfblatt"); c != 201 {
		t.Fatal(c, b)
	}
	if c, b := reg("b@example.com", "HANFBLATT"); c != 409 || !bytes.Contains([]byte(b), []byte("display_name_taken")) {
		t.Fatal(c, b)
	}
	// a name with @ would be taken for an email at login
	if c, b := reg("c@example.com", "a@b"); c != 400 || !bytes.Contains([]byte(b), []byte("invalid_display_name")) {
		t.Fatal(c, b)
	}
	// the email is still checked first
	if c, b := reg("a@example.com", "Other"); c != 409 || !bytes.Contains([]byte(b), []byte("email_taken")) {
		t.Fatal(c, b)
	}
}

// Wrong passwords count per account, whether the name or the email was
// typed, so switching between them gains an attacker nothing.
func TestWrongPasswordsCountPerAccount(t *testing.T) {
	d := app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret),
		Limits:    config.Limits{LoginFailures: ratelimit.Rule{N: 3, Per: time.Hour}},
	}}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.MountForTest(r, d) })
	register(t, r, "max@example.com") // named "Hanf max"
	for _, login := range []string{"Hanf max", "max@example.com", "HANF MAX"} {
		if rec := do(t, r, "POST", "/auth/login", "", map[string]any{"login": login, "password": "wrong-password-1"}); rec.Code != 401 {
			t.Fatalf("%s: %d", login, rec.Code)
		}
	}
	if rec := do(t, r, "POST", "/auth/login", "", map[string]any{"login": "max@example.com", "password": "correct-horse-1"}); rec.Code != 429 {
		t.Fatalf("after 3 wrong passwords: %d", rec.Code)
	}
}
