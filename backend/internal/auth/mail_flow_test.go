package auth_test

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

const appURL = "https://devilapi.github.io/stonerspots/#"

type mailEnv struct {
	d     app.Deps
	r     http.Handler
	mail  *auth.FakeMailer
	jobs  *auth.Jobs
	hibpN *atomic.Int32 // HIBP lookups made
}

func newMailEnv(t *testing.T, limits config.Limits) *mailEnv {
	t.Helper()
	e := &mailEnv{mail: &auth.FakeMailer{}, jobs: &auth.Jobs{}, hibpN: &atomic.Int32{}}
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		e.hibpN.Add(1)
		w.Write([]byte("0000000000000000000000000000000000A:1\r\n"))
	}))
	t.Cleanup(fake.Close)
	e.d = app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret), AppBaseURL: appURL, Limits: limits,
	}}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.MountWithFakeMail(r, e.d, e.mail, e.jobs, fake.URL+"/range/") })
	e.r = r
	return e
}

func sha(s string) string { h := sha256.Sum256([]byte(s)); return hex.EncodeToString(h[:]) }

// tokenIn returns the token of the app link in a mail body.
func tokenIn(t *testing.T, body, path string) string {
	t.Helper()
	prefix := appURL + path + "?token="
	i := strings.Index(body, prefix)
	if i < 0 {
		t.Fatalf("no %s link in %q", prefix, body)
	}
	rest := body[i+len(prefix):]
	if j := strings.IndexAny(rest, "\r\n "); j >= 0 {
		rest = rest[:j]
	}
	tok, err := url.QueryUnescape(rest)
	if err != nil || tok == "" {
		t.Fatalf("token %q: %v", rest, err)
	}
	return tok
}

// Registration with mail on: the link goes to the app, only the hash is
// stored, login waits for the verification, and the mail is sent with its
// own context (the request's is long gone when the job runs).
func TestVerificationMailFlow(t *testing.T) {
	e := newMailEnv(t, config.Limits{})
	reg := register(t, e.r, "new@example.com")
	if len(e.mail.Sent()) != 0 {
		t.Fatal("mail sent inside the request")
	}
	e.jobs.Run()
	sent := e.mail.Sent()
	if len(sent) != 1 || sent[0].To != "new@example.com" {
		t.Fatalf("sent %+v", sent)
	}
	if sent[0].CtxErr != nil || sent[0].Deadline <= 0 || sent[0].Deadline > time.Minute {
		t.Fatalf("mail context: err %v, deadline in %v", sent[0].CtxErr, sent[0].Deadline)
	}
	tok := tokenIn(t, sent[0].Body, "/verify-email")
	var stored string
	if err := e.d.DB.QueryRow(`SELECT email_verify_hash FROM users WHERE id = ?`, reg.User.ID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != sha(tok) {
		t.Fatalf("stored %q, want the token's SHA-256", stored)
	}

	login := map[string]any{"login": "new@example.com", "password": "correct-horse-1"}
	if rec := do(t, e.r, "POST", "/auth/login", "", login); rec.Code != 403 || !bytes.Contains(rec.Body.Bytes(), []byte("email_not_verified")) {
		t.Fatalf("login before verifying: %d %s", rec.Code, rec.Body)
	}
	if rec := do(t, e.r, "POST", "/auth/verify-email", "", map[string]any{"token": stored}); rec.Code != 400 {
		t.Fatalf("the stored hash must not work as token: %d", rec.Code)
	}
	if rec := do(t, e.r, "POST", "/auth/verify-email", "", map[string]any{"token": tok}); rec.Code != 204 {
		t.Fatalf("verify: %d %s", rec.Code, rec.Body)
	}
	if rec := do(t, e.r, "POST", "/auth/verify-email", "", map[string]any{"token": tok}); rec.Code != 400 {
		t.Fatalf("second use: %d", rec.Code)
	}
	if rec := do(t, e.r, "POST", "/auth/login", "", login); rec.Code != 200 {
		t.Fatalf("login after verifying: %d %s", rec.Code, rec.Body)
	}
}

// Accounts made while mail was off have no pending verification and can
// still log in once mail is switched on.
func TestAccountsFromBeforeMailStillLogIn(t *testing.T) {
	e := newMailEnv(t, config.Limits{})
	u := testutil.NewUser(t, e.d.DB)
	if _, err := e.d.DB.Exec(`UPDATE users SET email = 'old@example.com', password_hash = ? WHERE id = ?`, hashOf(t, "correct-horse-1"), u); err != nil {
		t.Fatal(err)
	}
	if rec := do(t, e.r, "POST", "/auth/login", "", map[string]any{"login": "old@example.com", "password": "correct-horse-1"}); rec.Code != 200 {
		t.Fatalf("login: %d %s", rec.Code, rec.Body)
	}
}

func TestPasswordResetFlow(t *testing.T) {
	e := newMailEnv(t, config.Limits{})
	reg := register(t, e.r, "forgot@example.com")
	e.jobs.Run() // verification mail
	before := len(e.mail.Sent())

	// unknown address: same answer, no mail
	if rec := do(t, e.r, "POST", "/auth/forgot-password", "", map[string]any{"email": "nobody@example.com"}); rec.Code != 204 {
		t.Fatalf("unknown: %d", rec.Code)
	}
	e.jobs.Run()
	if len(e.mail.Sent()) != before {
		t.Fatal("mail sent for an unknown address")
	}
	if rec := do(t, e.r, "POST", "/auth/forgot-password", "", map[string]any{"email": " Forgot@Example.com "}); rec.Code != 204 {
		t.Fatalf("known: %d", rec.Code)
	}
	e.jobs.Run()
	sent := e.mail.Sent()
	if len(sent) != before+1 {
		t.Fatalf("sent %d mails", len(sent)-before)
	}
	m := sent[len(sent)-1]
	if m.CtxErr != nil || m.Deadline <= 0 {
		t.Fatalf("mail context: %v %v", m.CtxErr, m.Deadline)
	}
	tok := tokenIn(t, m.Body, "/reset-password")
	var stored string
	e.d.DB.QueryRow(`SELECT password_reset_hash FROM users WHERE id = ?`, reg.User.ID).Scan(&stored)
	if stored != sha(tok) {
		t.Fatalf("stored %q is not the token's hash", stored)
	}

	// a wrong token is refused before HIBP is asked
	e.hibpN.Store(0) // registration asked it
	if rec := do(t, e.r, "POST", "/auth/reset-password", "", map[string]any{"token": "wrong", "new_password": "brand-new-pass-1"}); rec.Code != 400 {
		t.Fatalf("wrong token: %d", rec.Code)
	}
	if n := e.hibpN.Load(); n != 0 {
		t.Fatalf("HIBP asked %d times for a request with a wrong token", n)
	}
	if rec := do(t, e.r, "POST", "/auth/reset-password", "", map[string]any{"token": tok, "new_password": "brand-new-pass-1"}); rec.Code != 204 {
		t.Fatalf("reset: %d %s", rec.Code, rec.Body)
	}
	if e.hibpN.Load() != 1 {
		t.Fatal("HIBP not asked for the new password")
	}
	if rec := do(t, e.r, "POST", "/auth/reset-password", "", map[string]any{"token": tok, "new_password": "other-new-pass-2"}); rec.Code != 400 {
		t.Fatalf("token reused: %d", rec.Code)
	}
	// the reset proved the mailbox: the account is verified and can log in
	if rec := do(t, e.r, "POST", "/auth/login", "", map[string]any{"login": "forgot@example.com", "password": "brand-new-pass-1"}); rec.Code != 200 {
		t.Fatalf("login with new password: %d %s", rec.Code, rec.Body)
	}
	// the old session is gone
	if rec := do(t, e.r, "POST", "/auth/refresh", "", map[string]any{"refresh_token": reg.RefreshToken}); rec.Code != 401 {
		t.Fatalf("old refresh token: %d", rec.Code)
	}
}

func TestForgotPasswordLimits(t *testing.T) {
	e := newMailEnv(t, config.Limits{
		ForgotPassword:      ratelimit.Rule{N: 5, Per: time.Hour},
		ForgotPasswordEmail: ratelimit.Rule{N: 2, Per: time.Hour},
	})
	register(t, e.r, "victim@example.com")
	e.jobs.Run()
	before := len(e.mail.Sent())
	for i := 0; i < 4; i++ {
		// over the per-address limit the answer stays the same
		if rec := do(t, e.r, "POST", "/auth/forgot-password", "", map[string]any{"email": "victim@example.com"}); rec.Code != 204 {
			t.Fatalf("request %d: %d", i, rec.Code)
		}
	}
	e.jobs.Run()
	if n := len(e.mail.Sent()) - before; n != 2 {
		t.Fatalf("%d reset mails to one address, want 2", n)
	}
	// the 6th request from this IP is refused, whatever the address
	if rec := do(t, e.r, "POST", "/auth/forgot-password", "", map[string]any{"email": "other@example.com"}); rec.Code != 204 {
		t.Fatalf("5th: %d", rec.Code)
	}
	if rec := do(t, e.r, "POST", "/auth/forgot-password", "", map[string]any{"email": "third@example.com"}); rec.Code != 429 {
		t.Fatalf("6th: %d", rec.Code)
	}
}

// Wrong passwords for logins without an account are not counted per login
// (the per-IP limit covers them): random names must not be able to fill the
// limiter and push out the counters of real accounts.
func TestUnknownLoginsAreNotCountedPerAccount(t *testing.T) {
	d := app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{
		JWTSecret: []byte(testutil.JWTSecret),
		Limits:    config.Limits{LoginFailures: ratelimit.Rule{N: 2, Per: time.Hour}},
	}}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.MountForTest(r, d) })
	for i := 0; i < 5; i++ {
		if rec := do(t, r, "POST", "/auth/login", "", map[string]any{"login": "ghost@example.com", "password": "wrong-password-1"}); rec.Code != 401 {
			t.Fatalf("attempt %d: %d", i, rec.Code)
		}
	}
	// a real account is still limited
	register(t, r, "real@example.com")
	for i := 0; i < 2; i++ {
		do(t, r, "POST", "/auth/login", "", map[string]any{"login": "real@example.com", "password": "wrong-password-1"})
	}
	if rec := do(t, r, "POST", "/auth/login", "", map[string]any{"login": "real@example.com", "password": "correct-horse-1"}); rec.Code != 429 {
		t.Fatalf("real account after 2 failures: %d", rec.Code)
	}
}

func hashOf(t *testing.T, pw string) string {
	t.Helper()
	h, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	return string(h)
}

// The PoW challenges are signed with a key derived from the JWT secret, not
// the secret itself, and their difficulty comes from the config.
func TestPowKeyAndDifficulty(t *testing.T) {
	secret := []byte(testutil.JWTSecret)
	d := app.Deps{DB: testutil.NewDB(t), Cfg: config.Config{JWTSecret: secret, PowDifficulty: 12}}
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { auth.Mount(r, d) })
	tok := decode[struct{ Challenge string }](t, do(t, r, "GET", "/auth/pow-challenge", "", nil)).Challenge
	parts := strings.Split(tok, ":")
	if len(parts) != 7 || parts[3] != "12" {
		t.Fatalf("challenge %q", tok)
	}
	body, sig := tok[:strings.LastIndexByte(tok, ':')], parts[6]
	mac := func(key []byte) string {
		m := hmac.New(sha256.New, key)
		m.Write([]byte(body))
		return hex.EncodeToString(m.Sum(nil))
	}
	if sig == mac(secret) || sig != mac(auth.DeriveKey(secret, "pow-v1")) {
		t.Fatal("challenge not signed with the derived PoW key")
	}
	in := map[string]any{"email": "pow12@example.com", "password": "correct-horse-1", "display_name": "Pow12", "adult": true,
		"pow_challenge": tok, "pow": solve(t, tok, 12)}
	if rec := do(t, r, "POST", "/auth/register", "", in); rec.Code != 201 {
		t.Fatalf("register: %d %s", rec.Code, rec.Body)
	}
}

func TestAppLinkAndKeyDerivation(t *testing.T) {
	for base, want := range map[string]string{
		"https://devilapi.github.io/stonerspots/#":  "https://devilapi.github.io/stonerspots/#/reset-password?token=a%2Bb",
		"https://devilapi.github.io/stonerspots/#/": "https://devilapi.github.io/stonerspots/#/reset-password?token=a%2Bb",
		"https://app.stonerspots.de/":               "https://app.stonerspots.de/reset-password?token=a%2Bb",
	} {
		if got := auth.AppLink(base, "/reset-password", "a+b"); got != want {
			t.Errorf("%s: %s", base, got)
		}
	}
	secret := []byte(testutil.JWTSecret)
	pow, admin := auth.DeriveKey(secret, "pow-v1"), auth.DeriveKey(secret, "admin-2fa-v1")
	if bytes.Equal(pow, secret) || bytes.Equal(pow, admin) || len(pow) != 32 {
		t.Fatal("derived keys must differ from the secret and from each other")
	}
	m := hmac.New(sha256.New, secret)
	m.Write([]byte("stonerspots/pow-v1"))
	if !bytes.Equal(pow, m.Sum(nil)) {
		t.Fatal("pow key is not HMAC(secret, label)")
	}
}
