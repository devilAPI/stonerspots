package auth

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/totp"
)

// Admin 2FA.
//
// An admin with 2FA enabled proves it on every request that uses admin
// powers, with either
//   - X-TOTP: a 6-digit code. Each 30 s step is accepted once (replay
//     protection), so a code is good for one request; or
//   - X-Admin-Session: a token from POST /admin/2fa/session, which trades
//     one code for AdminSessionTTL of admin requests.
//
// Wrong codes count per admin (TOTPFailures in TOTPFailWindow, then 429);
// the count is keyed by the authenticated admin's own id, so nobody else can
// lock an admin out. Admin powers outside the /admin routes (deleting other
// people's comments, tags of other people's spots, writing on locked spots)
// go through Guard.AdminPowers and need the same proof.
const (
	HeaderTOTP         = "X-TOTP"
	HeaderAdminSession = "X-Admin-Session"

	TOTPFailures    = 5
	TOTPFailWindow  = 15 * time.Minute
	AdminSessionTTL = 15 * time.Minute

	adminSessionAudience = "stonerspots-admin-2fa"
)

// account is the part of the users row every authenticated request needs.
// CheckAccount loads it once per request; RequireAdmin and AdminPowers
// reuse it.
type account struct {
	id          uint64
	admin       bool
	totpEnabled bool
	banned      bool
	missing     bool // no such user (deleted)
}

type accountKey struct{}

// how2FA records how a request proved 2FA (for POST /admin/2fa/session).
type how2FA int

const (
	by2FANone how2FA = iota
	by2FACode
	by2FASession
)

type how2FAKey struct{}

func queryAccount(ctx context.Context, db *sql.DB, id uint64) (*account, error) {
	a := &account{id: id}
	err := db.QueryRowContext(ctx,
		`SELECT is_admin, totp_enabled, banned_at IS NOT NULL FROM users WHERE id = ?`, id).
		Scan(&a.admin, &a.totpEnabled, &a.banned)
	if err != nil {
		return nil, err
	}
	return a, nil
}

// CheckAccount runs on every request (server.New). For a request with a
// valid access token it reads the account (one primary key lookup) and
// keeps it in the context: Middleware then refuses tokens of banned or
// deleted users with 401 at once, so a ban takes effect immediately and not
// only when the token expires; Optional treats them as anonymous; and
// RequireAdmin and AdminPowers reuse the row instead of reading it again.
// Routes without auth (login, register, ...) are not affected.
func CheckAccount(d app.Deps) func(http.Handler) http.Handler {
	secret, db := d.Cfg.JWTSecret, d.DB
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			tok := bearer(r)
			if tok == "" {
				next.ServeHTTP(w, r)
				return
			}
			id, err := parseAccess(secret, tok)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}
			a, err := queryAccount(r.Context(), db, id)
			if errors.Is(err, sql.ErrNoRows) {
				a, err = &account{id: id, missing: true}, nil
			}
			if err != nil {
				serverError(w)
				return
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), accountKey{}, a)))
		})
	}
}

// Guard checks admin rights and 2FA. There is one per database and config
// (GuardFor), so the wrong-code counter is shared by every route.
type Guard struct {
	db          *sql.DB
	sessionKey  []byte
	failures    *ratelimit.Limiter
	requireTOTP bool
	now         func() time.Time
}

type guardID struct {
	db      *sql.DB
	secret  string
	require bool
}

var guards sync.Map // guardID -> *Guard

// GuardFor returns the process-wide Guard for d.
func GuardFor(d app.Deps) *Guard {
	id := guardID{d.DB, string(d.Cfg.JWTSecret), d.Cfg.RequireAdminTOTP}
	if g, ok := guards.Load(id); ok {
		return g.(*Guard)
	}
	g, _ := guards.LoadOrStore(id, &Guard{
		db:          d.DB,
		sessionKey:  deriveKey(d.Cfg.JWTSecret, "admin-2fa-v1"),
		failures:    ratelimit.New(ratelimit.Rule{N: TOTPFailures, Per: TOTPFailWindow}),
		requireTOTP: d.Cfg.RequireAdminTOTP,
		now:         time.Now,
	})
	return g.(*Guard)
}

// loadedAccount is the row CheckAccount read for user id, if it ran.
func loadedAccount(ctx context.Context, id uint64) (*account, bool) {
	a, ok := ctx.Value(accountKey{}).(*account)
	return a, ok && a.id == id
}

// account returns the caller's row, from CheckAccount when it ran.
func (g *Guard) account(ctx context.Context, id uint64) (*account, error) {
	if a, ok := loadedAccount(ctx, id); ok {
		if a.missing {
			return nil, sql.ErrNoRows
		}
		return a, nil
	}
	return queryAccount(ctx, g.db, id)
}

// RequireAdmin must be used after Middleware. It reads is_admin from the
// database on every request (the JWT carries no role), so revoking admin
// takes effect immediately. A missing user row is 401, a non-admin 403. An
// admin with 2FA must prove it (X-TOTP or X-Admin-Session, see above); with
// require_admin_totp an admin without 2FA is refused (totp_setup_required).
func RequireAdmin(d app.Deps) func(http.Handler) http.Handler {
	return GuardFor(d).require(false)
}

// RequireAdminSetup is RequireAdmin for the routes that set up 2FA: they
// stay open to admins without 2FA even with require_admin_totp.
func RequireAdminSetup(d app.Deps) func(http.Handler) http.Handler {
	return GuardFor(d).require(true)
}

func (g *Guard) require(setup bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			id, ok := UserID(r.Context())
			if !ok {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			a, err := g.account(r.Context(), id)
			if errors.Is(err, sql.ErrNoRows) {
				httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
				return
			}
			if err != nil {
				serverError(w)
				return
			}
			if a.banned {
				httpx.Error(w, http.StatusUnauthorized, "account_banned", "this account is banned")
				return
			}
			if !a.admin {
				httpx.Error(w, http.StatusForbidden, "forbidden", "admin access required")
				return
			}
			if r, ok = g.secondFactor(w, r, a, setup); ok {
				next.ServeHTTP(w, r)
			}
		})
	}
}

// AdminPowers is for handlers that let admins do more than other users. It
// reports granted when the caller is an admin who passed the same 2FA check
// as RequireAdmin. For non-admins it reports neither (the handler goes on
// as for anyone); when an admin fails the check it has written the error
// and reports handled. Call it only once the admin power is needed: a
// valid X-TOTP code is used up by it.
func (g *Guard) AdminPowers(w http.ResponseWriter, r *http.Request) (granted, handled bool) {
	id, ok := UserID(r.Context())
	if !ok {
		return false, false
	}
	a, err := g.account(r.Context(), id)
	if errors.Is(err, sql.ErrNoRows) {
		return false, false
	}
	if err != nil {
		serverError(w)
		return false, true
	}
	if !a.admin || a.banned {
		return false, false
	}
	if _, ok := g.secondFactor(w, r, a, false); !ok {
		return false, true
	}
	return true, false
}

// secondFactor checks the 2FA proof of admin a; on failure it writes the
// error. The returned request records how 2FA was proven.
func (g *Guard) secondFactor(w http.ResponseWriter, r *http.Request, a *account, setup bool) (*http.Request, bool) {
	if !a.totpEnabled {
		if g.requireTOTP && !setup {
			httpx.Error(w, http.StatusForbidden, "totp_setup_required",
				"admins must set up 2FA first (POST /admin/2fa/enable, then /admin/2fa/verify)")
			return nil, false
		}
		return r, true
	}
	session := r.Header.Get(HeaderAdminSession)
	if session != "" && g.validSession(session, a.id) {
		return r.WithContext(context.WithValue(r.Context(), how2FAKey{}, by2FASession)), true
	}
	code := r.Header.Get(HeaderTOTP)
	if code == "" {
		if session != "" {
			httpx.Error(w, http.StatusForbidden, "totp_session_expired", "2FA session expired; send a new code in X-TOTP")
		} else {
			httpx.Error(w, http.StatusForbidden, "totp_required", "2FA code required (X-TOTP header)")
		}
		return nil, false
	}
	if !g.codeOK(w, r, a.id, code, false) {
		return nil, false
	}
	return r.WithContext(context.WithValue(r.Context(), how2FAKey{}, by2FACode)), true
}

var (
	errTOTPInvalid = errors.New("invalid 2FA code")
	errTOTPReused  = errors.New("2FA code already used")
	errTOTPBlocked = errors.New("too many wrong 2FA codes")
	errTOTPNoSetup = errors.New("2FA not set up")
)

func totpFailKey(id uint64) string { return "totp:" + strconv.FormatUint(id, 10) }

// checkCode checks a code against the user's (possibly not yet enabled)
// secret and uses up its time step. sameStepOK accepts the step that was
// used last once more (for a second check within the same action).
func (g *Guard) checkCode(ctx context.Context, id uint64, code string, sameStepOK bool) (time.Duration, error) {
	key := totpFailKey(id)
	if blocked, retry := g.failures.Blocked(key); blocked {
		return retry, errTOTPBlocked
	}
	var secret sql.NullString
	var last sql.NullInt64
	err := g.db.QueryRowContext(ctx, `SELECT totp_secret, totp_last_step FROM users WHERE id = ?`, id).Scan(&secret, &last)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && !secret.Valid) {
		return 0, errTOTPNoSetup
	}
	if err != nil {
		return 0, err
	}
	step, ok := totp.Match(secret.String, code, g.now())
	if !ok {
		g.failures.Allow(key)
		return 0, errTOTPInvalid
	}
	if sameStepOK {
		if last.Valid && last.Int64 > step {
			return 0, errTOTPReused
		}
		_, err = g.db.ExecContext(ctx, `UPDATE users SET totp_last_step = ? WHERE id = ?`, step, id)
		return 0, err
	}
	// atomic: of two requests with the same code only one gets through
	res, err := g.db.ExecContext(ctx,
		`UPDATE users SET totp_last_step = ? WHERE id = ? AND (totp_last_step IS NULL OR totp_last_step < ?)`, step, id, step)
	if err != nil {
		return 0, err
	}
	if n, _ := res.RowsAffected(); n != 1 {
		return 0, errTOTPReused
	}
	return 0, nil
}

// codeOK runs checkCode and writes the error answer when it fails.
func (g *Guard) codeOK(w http.ResponseWriter, r *http.Request, id uint64, code string, sameStepOK bool) bool {
	retry, err := g.checkCode(r.Context(), id, code, sameStepOK)
	switch {
	case err == nil:
		return true
	case errors.Is(err, errTOTPBlocked):
		log.Printf("auth_fail kind=totp_blocked ip=%s user=%d", httpx.ClientIP(r), id)
		ratelimit.TooMany(w, retry)
	case errors.Is(err, errTOTPInvalid):
		log.Printf("auth_fail kind=totp ip=%s user=%d", httpx.ClientIP(r), id)
		httpx.Error(w, http.StatusForbidden, "totp_invalid", "invalid or expired 2FA code")
	case errors.Is(err, errTOTPReused):
		httpx.Error(w, http.StatusForbidden, "totp_reused", "this 2FA code was already used; wait for the next one")
	case errors.Is(err, errTOTPNoSetup):
		httpx.Error(w, http.StatusBadRequest, "no_secret", "2FA enrollment not started")
	default:
		serverError(w)
	}
	return false
}

// CheckCode is codeOK for the 2FA setup handlers (admin package): the code
// from the request body, checked like X-TOTP. sameStepOK: see checkCode.
func (g *Guard) CheckCode(w http.ResponseWriter, r *http.Request, id uint64, code string, sameStepOK bool) bool {
	return g.codeOK(w, r, id, code, sameStepOK)
}

// CheckPassword verifies the user's password (for turning 2FA off). Wrong
// passwords count like wrong codes.
func (g *Guard) CheckPassword(w http.ResponseWriter, r *http.Request, id uint64, password string) bool {
	key := totpFailKey(id)
	if blocked, retry := g.failures.Blocked(key); blocked {
		ratelimit.TooMany(w, retry)
		return false
	}
	var hash string
	err := g.db.QueryRowContext(r.Context(), `SELECT password_hash FROM users WHERE id = ?`, id).Scan(&hash)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
		return false
	}
	if err != nil {
		serverError(w)
		return false
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		g.failures.Allow(key)
		log.Printf("auth_fail kind=password ip=%s user=%d", httpx.ClientIP(r), id)
		httpx.Error(w, http.StatusForbidden, "wrong_password", "password is incorrect")
		return false
	}
	return true
}

// NewAdminSession answers POST /admin/2fa/session (behind RequireAdmin):
// it trades the X-TOTP code of this request for a token that stands in for
// codes on admin requests for AdminSessionTTL (header X-Admin-Session). A
// session cannot extend itself: every new one needs a fresh code.
func (g *Guard) NewAdminSession(w http.ResponseWriter, r *http.Request) {
	id, _ := UserID(r.Context())
	if how, _ := r.Context().Value(how2FAKey{}).(how2FA); how != by2FACode {
		if a, err := g.account(r.Context(), id); err == nil && !a.totpEnabled {
			httpx.Error(w, http.StatusConflict, "totp_not_enabled", "2FA is not enabled for this account")
			return
		}
		httpx.Error(w, http.StatusForbidden, "totp_required", "a new session needs a fresh 2FA code (X-TOTP header)")
		return
	}
	exp := g.now().Add(AdminSessionTTL)
	tok, err := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Subject:   strconv.FormatUint(id, 10),
		Audience:  jwt.ClaimStrings{adminSessionAudience},
		IssuedAt:  jwt.NewNumericDate(g.now()),
		ExpiresAt: jwt.NewNumericDate(exp),
	}).SignedString(g.sessionKey)
	if err != nil {
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"token": tok, "expires_at": exp.UTC()})
}

func (g *Guard) validSession(tok string, id uint64) bool {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(tok, &claims, func(*jwt.Token) (any, error) {
		return g.sessionKey, nil
	}, jwt.WithValidMethods([]string{"HS256"}), jwt.WithExpirationRequired(),
		jwt.WithAudience(adminSessionAudience), jwt.WithTimeFunc(g.now))
	return err == nil && claims.Subject == strconv.FormatUint(id, 10)
}
