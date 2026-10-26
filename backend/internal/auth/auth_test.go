package auth_test

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

func newRouter(t *testing.T) http.Handler {
	t.Helper()
	d := app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret)}}
	r := chi.NewRouter()
	// Mount with pow=nil to disable PoW in tests
	r.Route("/api/v1", func(r chi.Router) { auth.MountForTest(r, d) })
	return r
}

func do(t *testing.T, h http.Handler, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, "/api/v1"+path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

type authResp struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	User         struct {
		ID          uint64 `json:"id"`
		Email       string `json:"email"`
		DisplayName string `json:"display_name"`
	} `json:"user"`
}

func decode[T any](t *testing.T, rec *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(rec.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return v
}

func register(t *testing.T, h http.Handler, email string) authResp {
	t.Helper()
	rec := do(t, h, "POST", "/auth/register", "", map[string]any{
		// names are unique: one per email
		"email": email, "password": "correct-horse-1", "display_name": "Hanf " + strings.TrimSpace(strings.Split(email, "@")[0]), "adult": true})
	if rec.Code != 201 {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
	return decode[authResp](t, rec)
}

func TestRegisterLoginRoundTrip(t *testing.T) {
	h := newRouter(t)
	reg := register(t, h, "  Foo@Example.COM ")
	if reg.AccessToken == "" || reg.RefreshToken == "" || reg.User.ID == 0 || reg.User.Email != "foo@example.com" {
		t.Fatalf("bad register response: %+v", reg)
	}
	rec := do(t, h, "POST", "/auth/login", "", map[string]any{"email": "FOO@example.com", "password": "correct-horse-1"})
	if rec.Code != 200 {
		t.Fatalf("login: %d %s", rec.Code, rec.Body)
	}
	if l := decode[authResp](t, rec); l.User.ID != reg.User.ID || l.AccessToken == "" || l.RefreshToken == "" {
		t.Fatalf("bad login response: %+v", l)
	}
}

func TestRegisterRequiresAdult(t *testing.T) {
	h := newRouter(t)
	for _, adult := range []any{false, nil} {
		body := map[string]any{"email": "a@example.com", "password": "correct-horse-1", "display_name": "A"}
		if adult != nil {
			body["adult"] = adult
		}
		rec := do(t, h, "POST", "/auth/register", "", body)
		if rec.Code != 400 || !bytes.Contains(rec.Body.Bytes(), []byte("adult_required")) {
			t.Fatalf("got %d %s", rec.Code, rec.Body)
		}
	}
	rec := do(t, h, "POST", "/auth/register", "", map[string]any{
		"email": "a@example.com", "password": "short", "display_name": "A", "adult": true})
	if rec.Code != 400 {
		t.Fatalf("short password: %d", rec.Code)
	}
}

func TestDuplicateEmail409(t *testing.T) {
	h := newRouter(t)
	register(t, h, "dup@example.com")
	rec := do(t, h, "POST", "/auth/register", "", map[string]any{
		"email": "DUP@example.com", "password": "correct-horse-1", "display_name": "B", "adult": true})
	if rec.Code != 409 || !bytes.Contains(rec.Body.Bytes(), []byte("email_taken")) {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
}

func TestWrongPasswordDoesNotRevealWhetherEmailExists(t *testing.T) {
	h := newRouter(t)
	register(t, h, "real@example.com")
	a := do(t, h, "POST", "/auth/login", "", map[string]any{"email": "real@example.com", "password": "wrong-password-1"})
	b := do(t, h, "POST", "/auth/login", "", map[string]any{"email": "nobody@example.com", "password": "wrong-password-1"})
	if a.Code != 401 || b.Code != 401 || a.Body.String() != b.Body.String() {
		t.Fatalf("a=%d %s b=%d %s", a.Code, a.Body, b.Code, b.Body)
	}
}

func refresh(t *testing.T, h http.Handler, tok string) *httptest.ResponseRecorder {
	return do(t, h, "POST", "/auth/refresh", "", map[string]any{"refresh_token": tok})
}

func TestRefreshRotates(t *testing.T) {
	h := newRouter(t)
	reg := register(t, h, "r@example.com")
	rec := refresh(t, h, reg.RefreshToken)
	if rec.Code != 200 {
		t.Fatalf("refresh: %d %s", rec.Code, rec.Body)
	}
	n := decode[authResp](t, rec)
	if n.RefreshToken == "" || n.RefreshToken == reg.RefreshToken || n.AccessToken == "" {
		t.Fatalf("not rotated: %+v", n)
	}
	if rec := refresh(t, h, n.RefreshToken); rec.Code != 200 {
		t.Fatalf("new token should work: %d", rec.Code)
	}
	if rec := refresh(t, h, "garbage"); rec.Code != 401 {
		t.Fatalf("garbage: %d", rec.Code)
	}
}

func TestReusedRefreshTokenRevokesFamily(t *testing.T) {
	h := newRouter(t)
	reg := register(t, h, "f@example.com")
	n := decode[authResp](t, refresh(t, h, reg.RefreshToken))
	if rec := refresh(t, h, reg.RefreshToken); rec.Code != 401 {
		t.Fatalf("reuse should 401, got %d", rec.Code)
	}
	if rec := refresh(t, h, n.RefreshToken); rec.Code != 401 {
		t.Fatalf("family should be revoked, got %d", rec.Code)
	}
}

func TestMeReturnsCurrentUser(t *testing.T) {
	h := newRouter(t)
	reg := register(t, h, "me@example.com")
	rec := do(t, h, "GET", "/me", reg.AccessToken, nil)
	if rec.Code != 200 {
		t.Fatalf("me: %d %s", rec.Code, rec.Body)
	}
	u := decode[struct {
		ID    uint64 `json:"id"`
		Email string `json:"email"`
	}](t, rec)
	if u.ID != reg.User.ID || u.Email != "me@example.com" {
		t.Fatalf("got %+v", u)
	}
	if rec := do(t, h, "GET", "/me", "", nil); rec.Code != 401 {
		t.Fatalf("anon: %d", rec.Code)
	}
}
