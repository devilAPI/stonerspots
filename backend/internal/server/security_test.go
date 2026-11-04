package server_test

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/server"
	"stonerspots/backend/internal/testutil"
	"stonerspots/backend/internal/totp"
)

// sec drives the real router as different users with extra headers.
type sec struct {
	t  *testing.T
	db *sql.DB
	h  http.Handler
}

func newSec(t *testing.T, mod func(*config.Config)) *sec {
	t.Helper()
	db := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), UploadDir: t.TempDir(), PublicBaseURL: "http://test", DisablePoW: true}
	if mod != nil {
		mod(&cfg)
	}
	return &sec{t: t, db: db, h: server.New(app.Deps{DB: db, Cfg: cfg})}
}

type resp struct {
	code int
	body map[string]any
	raw  string
}

func (r resp) errCode() string {
	if e, ok := r.body["error"].(map[string]any); ok {
		s, _ := e["code"].(string)
		return s
	}
	return ""
}

func (s *sec) call(method, path string, user uint64, hdr map[string]string, body any) resp {
	s.t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, "/api/v1"+path, &buf)
	req.Header.Set("Content-Type", "application/json")
	if user != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(s.t, user))
	}
	for k, v := range hdr {
		req.Header.Set(k, v)
	}
	rec := httptest.NewRecorder()
	s.h.ServeHTTP(rec, req)
	var m map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &m)
	return resp{rec.Code, m, rec.Body.String()}
}

func (s *sec) exec(q string, args ...any) {
	s.t.Helper()
	if _, err := s.db.Exec(q, args...); err != nil {
		s.t.Fatal(err)
	}
}

func (s *sec) want(r resp, code int, errCode string, what string) {
	s.t.Helper()
	if r.code != code || (errCode != "" && r.errCode() != errCode) {
		s.t.Fatalf("%s: %d %s, want %d %s", what, r.code, r.raw, code, errCode)
	}
}

func (s *sec) id(r resp) string {
	s.t.Helper()
	v, ok := r.body["id"].(float64)
	if !ok {
		s.t.Fatalf("no id in %s", r.raw)
	}
	return strconv.FormatInt(int64(v), 10)
}

// awayFromStepEdge waits when a 30 s TOTP step is about to end, so the
// codes a test computes up front stay in the accepted window.
func awayFromStepEdge() {
	if left := 30 - time.Now().Unix()%30; left < 3 {
		time.Sleep(time.Duration(left)*time.Second + 100*time.Millisecond)
	}
}

// enroll turns on 2FA for admin with the code of the previous step and
// returns the secret and the start time t0: the codes for t0 and t0+30s
// are still fresh after that.
func (s *sec) enroll(admin uint64) (string, time.Time) {
	s.t.Helper()
	awayFromStepEdge()
	r := s.call("POST", "/admin/2fa/enable", admin, nil, nil)
	s.want(r, 200, "", "2fa enable")
	secret := r.body["secret"].(string)
	t0 := time.Now()
	s.want(s.call("POST", "/admin/2fa/verify", admin, nil, map[string]any{"code": totp.Code(secret, t0.Add(-totp.Step))}), 204, "", "2fa verify")
	return secret, t0
}

func TestBannedAccessTokenStopsAtOnce(t *testing.T) {
	s := newSec(t, nil)
	u := testutil.NewUser(t, s.db)
	s.want(s.call("GET", "/me", u, nil, nil), 200, "", "before ban")
	s.exec(`UPDATE users SET banned_at = UTC_TIMESTAMP() WHERE id = ?`, u)
	s.want(s.call("GET", "/me", u, nil, nil), 401, "account_banned", "me after ban")
	s.want(s.call("POST", "/spots", u, nil, map[string]any{"title": "x", "lat": 47.1, "lon": 8.1}), 401, "account_banned", "write after ban")
	// optional-auth routes serve a banned user as anonymous
	s.want(s.call("GET", "/feed", u, nil, nil), 200, "", "feed after ban")
	s.want(s.call("GET", fmt.Sprintf("/users/%d", u), u, nil, nil), 404, "", "own profile after ban")
	// routes without auth ignore the stale token (e.g. registering again)
	s.want(s.call("GET", "/auth/pow-challenge", u, nil, nil), 501, "", "no-auth route")
	s.exec(`UPDATE users SET banned_at = NULL WHERE id = ?`, u)
	s.want(s.call("GET", "/me", u, nil, nil), 200, "", "after unban")
	// a deleted account's token is dead as well
	s.exec(`DELETE FROM users WHERE id = ?`, u)
	s.want(s.call("GET", "/me", u, nil, nil), 401, "unauthorized", "deleted user")
	s.want(s.call("GET", "/auth/pow-challenge", u, nil, nil), 501, "", "no-auth route with a deleted user's token")
	// requests without a token are unaffected
	s.want(s.call("GET", "/feed", 0, nil, nil), 200, "", "anonymous feed")
}

func TestBanThroughAdminEndsSessions(t *testing.T) {
	s := newSec(t, nil)
	admin, u := testutil.NewUser(t, s.db), testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin)
	s.exec(`INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at) VALUES (?, 'h', 'f', UTC_TIMESTAMP() + INTERVAL 1 DAY)`, u)
	s.want(s.call("POST", "/admin/users/bulk", admin, nil, map[string]any{"action": "ban", "ids": []uint64{u}}), 200, "", "ban")
	var live int
	s.db.QueryRow(`SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NULL`, u).Scan(&live)
	if live != 0 {
		t.Fatalf("%d refresh tokens survive the ban", live)
	}
	s.want(s.call("GET", "/me", u, nil, nil), 401, "account_banned", "access token after ban")
}

func TestAdminTOTPFlow(t *testing.T) {
	s := newSec(t, nil)
	admin := testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1, password_hash = ? WHERE id = ?`, bcryptHash(t, "admin-password-1"), admin)
	// without 2FA set up, admin routes work as before (2FA is optional)
	s.want(s.call("GET", "/admin/reports", admin, nil, nil), 200, "", "admin without 2FA")

	secret, t0 := s.enroll(admin)
	cur, next := totp.Code(secret, t0), totp.Code(secret, t0.Add(totp.Step))
	tc := func(c string) map[string]string { return map[string]string{"X-TOTP": c} }

	s.want(s.call("GET", "/admin/reports", admin, nil, nil), 403, "totp_required", "no code")
	// the code used to enroll cannot be used again
	s.want(s.call("GET", "/admin/reports", admin, tc(totp.Code(secret, t0.Add(-totp.Step))), nil), 403, "totp_reused", "enroll code replayed")
	s.want(s.call("GET", "/admin/reports", admin, tc(cur), nil), 200, "", "fresh code")
	s.want(s.call("GET", "/admin/reports", admin, tc(cur), nil), 403, "totp_reused", "same code again")

	// a session needs a fresh code, and then stands in for codes
	s.want(s.call("POST", "/admin/2fa/session", admin, tc(cur), nil), 403, "totp_reused", "session with used code")
	r := s.call("POST", "/admin/2fa/session", admin, tc(next), nil)
	s.want(r, 200, "", "session")
	session := r.body["token"].(string)
	sh := map[string]string{"X-Admin-Session": session}
	for i := 0; i < 3; i++ {
		s.want(s.call("GET", "/admin/reports", admin, sh, nil), 200, "", "with session")
	}
	// a session cannot renew itself
	s.want(s.call("POST", "/admin/2fa/session", admin, sh, nil), 403, "totp_required", "session from session")
	// nor be used by someone else, nor be forged with the token key
	other := testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, other)
	s.exec(`UPDATE users SET totp_enabled = 1, totp_secret = ? WHERE id = ?`, secret, other)
	s.want(s.call("GET", "/admin/reports", other, sh, nil), 403, "totp_session_expired", "someone else's session")
	forged, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Subject: fmt.Sprint(admin), Audience: jwt.ClaimStrings{"stonerspots-admin-2fa"},
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
	}).SignedString([]byte(testutil.JWTSecret))
	s.want(s.call("GET", "/admin/reports", admin, map[string]string{"X-Admin-Session": forged}, nil), 403, "totp_session_expired", "forged session")

	// turning 2FA off needs the password as well
	off := map[string]any{"password": "wrong-password-1", "code": next}
	s.want(s.call("POST", "/admin/2fa/disable", admin, sh, off), 403, "wrong_password", "disable, wrong password")
	off["password"] = "admin-password-1"
	s.want(s.call("POST", "/admin/2fa/disable", admin, sh, off), 204, "", "disable")
	s.want(s.call("GET", "/admin/reports", admin, nil, nil), 200, "", "2FA off again")
}

// Wrong codes are limited per admin; the counter is keyed by the admin's
// own id, so other users cannot lock an admin out.
func TestAdminTOTPAttemptLimit(t *testing.T) {
	s := newSec(t, nil)
	admin, user := testutil.NewUser(t, s.db), testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin)
	secret, t0 := s.enroll(admin)
	session := s.call("POST", "/admin/2fa/session", admin, map[string]string{"X-TOTP": totp.Code(secret, t0)}, nil).body["token"].(string)

	// a non-admin hammering admin routes with codes never reaches the check
	for i := 0; i < 10; i++ {
		s.want(s.call("GET", "/admin/reports", user, map[string]string{"X-TOTP": "000000"}, nil), 403, "forbidden", "non-admin")
	}
	wrong := totp.Code(secret, t0.Add(10*totp.Step))
	for i := 0; i < 5; i++ {
		s.want(s.call("GET", "/admin/reports", admin, map[string]string{"X-TOTP": wrong}, nil), 403, "totp_invalid", "wrong code")
	}
	r := s.call("GET", "/admin/reports", admin, map[string]string{"X-TOTP": totp.Code(secret, t0.Add(totp.Step))}, nil)
	s.want(r, 429, "rate_limited", "right code after 5 wrong ones")
	// the session obtained before still works
	s.want(s.call("GET", "/admin/reports", admin, map[string]string{"X-Admin-Session": session}, nil), 200, "", "existing session")
}

// Admin powers outside the /admin routes need the same 2FA proof.
func TestAdminPowersOutsideAdminRoutesNeed2FA(t *testing.T) {
	s := newSec(t, nil)
	owner, admin, user := testutil.NewUser(t, s.db), testutil.NewUser(t, s.db), testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin)

	spot := s.call("POST", "/spots", owner, nil, map[string]any{"title": "Bench", "lat": 47.3, "lon": 8.5})
	s.want(spot, 201, "", "spot")
	spotID := s.id(spot)
	upd := s.call("POST", "/spots/"+spotID+"/updates", owner, nil, map[string]any{"body": "still here"})
	s.want(upd, 201, "", "update")
	updID := s.id(upd)
	newComment := func() string {
		c := s.call("POST", "/spots/"+spotID+"/comments", owner, nil, map[string]any{"body": "hi"})
		s.want(c, 201, "", "comment")
		return s.id(c)
	}
	adminUpd := s.call("POST", "/spots/"+spotID+"/updates", admin, nil, map[string]any{"body": "by the admin"})
	s.want(adminUpd, 201, "", "admin's update")
	adminUpdID := s.id(adminUpd)

	secret, t0 := s.enroll(admin)
	session := map[string]string{"X-Admin-Session": s.call("POST", "/admin/2fa/session", admin, map[string]string{"X-TOTP": totp.Code(secret, t0)}, nil).body["token"].(string)}

	// someone else's comment
	c1 := newComment()
	s.want(s.call("DELETE", "/comments/"+c1, user, nil, nil), 404, "not_found", "user deletes others' comment")
	s.want(s.call("DELETE", "/comments/"+c1, admin, nil, nil), 403, "totp_required", "admin without 2FA proof")
	s.want(s.call("DELETE", "/comments/"+c1, admin, session, nil), 204, "", "admin with session")
	s.want(s.call("DELETE", "/comments/"+newComment(), owner, nil, nil), 204, "", "author deletes own comment")

	// tags of someone else's spot
	tags := map[string]any{"tags": []string{"lit"}}
	s.want(s.call("PUT", "/spots/"+spotID+"/tags", user, nil, tags), 403, "forbidden", "user tags others' spot")
	s.want(s.call("PUT", "/spots/"+spotID+"/tags", admin, nil, tags), 403, "totp_required", "admin tags without proof")
	s.want(s.call("PUT", "/spots/"+spotID+"/tags", admin, session, tags), 200, "", "admin tags with session")

	// locked spot: posting, editing and deleting own updates
	s.exec(`UPDATE spots SET locked = 1 WHERE id = ?`, spotID)
	body := map[string]any{"body": "on a locked spot"}
	s.want(s.call("POST", "/spots/"+spotID+"/updates", owner, nil, body), 403, "spot_locked", "owner on locked spot")
	s.want(s.call("POST", "/spots/"+spotID+"/updates", admin, nil, body), 403, "totp_required", "admin posts without proof")
	s.want(s.call("POST", "/spots/"+spotID+"/updates", admin, session, body), 201, "", "admin posts with session")
	s.want(s.call("POST", "/spots/"+spotID+"/comments", owner, nil, body), 403, "spot_locked", "owner comments on locked spot")
	s.want(s.call("POST", "/spots/"+spotID+"/comments", admin, nil, body), 403, "totp_required", "admin comments without proof")
	s.want(s.call("POST", "/spots/"+spotID+"/comments", admin, session, body), 201, "", "admin comments with session")
	s.want(s.call("PATCH", "/updates/"+adminUpdID, admin, nil, map[string]any{"body": "edited"}), 403, "totp_required", "admin edits without proof")
	s.want(s.call("PATCH", "/updates/"+adminUpdID, admin, session, map[string]any{"body": "edited"}), 200, "", "admin edits with session")
	s.want(s.call("DELETE", "/updates/"+adminUpdID, admin, nil, nil), 403, "totp_required", "admin deletes without proof")
	s.want(s.call("DELETE", "/updates/"+adminUpdID, admin, session, nil), 204, "", "admin deletes with session")
	s.want(s.call("DELETE", "/updates/"+updID, owner, nil, nil), 403, "spot_locked", "owner deletes on locked spot")
}

// Search and feed, the most expensive public queries, have their own per-IP
// limit below the global one.
func TestSearchAndFeedPerIPLimit(t *testing.T) {
	s := newSec(t, func(c *config.Config) {
		c.Limits.Search = ratelimit.Rule{N: 2, Per: time.Minute}
	})
	for _, path := range []string{"/spots/search?q=bench", "/feed"} {
		for i := 0; i < 2; i++ {
			s.want(s.call("GET", path, 0, nil, nil), 200, "", path)
		}
		s.want(s.call("GET", path, 0, nil, nil), 429, "rate_limited", path+" over the limit")
	}
	// other public routes are not affected
	s.want(s.call("GET", "/tags", 0, nil, nil), 200, "", "tags")
}

func TestRequireAdminTOTPFlag(t *testing.T) {
	s := newSec(t, func(c *config.Config) { c.RequireAdminTOTP = true })
	admin, owner := testutil.NewUser(t, s.db), testutil.NewUser(t, s.db)
	s.exec(`UPDATE users SET is_admin = 1 WHERE id = ?`, admin)
	s.want(s.call("GET", "/admin/reports", admin, nil, nil), 403, "totp_setup_required", "admin without 2FA")
	spot := s.call("POST", "/spots", owner, nil, map[string]any{"title": "Bench", "lat": 47.3, "lon": 8.5})
	s.want(s.call("PUT", "/spots/"+s.id(spot)+"/tags", admin, nil, map[string]any{"tags": []string{"lit"}}), 403, "totp_setup_required", "admin power without 2FA")
	// setting it up stays possible
	s.want(s.call("GET", "/admin/2fa", admin, nil, nil), 200, "", "2fa status")
	secret, t0 := s.enroll(admin)
	s.want(s.call("GET", "/admin/reports", admin, map[string]string{"X-TOTP": totp.Code(secret, t0)}, nil), 200, "", "after setup")
}

func bcryptHash(t *testing.T, pw string) string {
	t.Helper()
	h, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	return string(h)
}
