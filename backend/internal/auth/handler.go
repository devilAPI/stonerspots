package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/hibp"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/pow"
	"stonerspots/backend/internal/ratelimit"
)

type handler struct {
	svc      *service
	hibp     *hibp.Client
	failures *ratelimit.Limiter
	pow      *pow.Issuer
	// forgotPerEmail limits reset mails per target address.
	forgotPerEmail *ratelimit.Limiter
	// unreadActivity counts the caller's unread activity for GET /me
	// (nil: always 0).
	unreadActivity func(context.Context, uint64) (int, error)
}

// passwordBlocked writes the 429 and reports true when key has no wrong
// guesses left.
func (h *handler) passwordBlocked(w http.ResponseWriter, key string) bool {
	if key == "" {
		return false
	}
	if blocked, retry := h.failures.Blocked(key); blocked {
		ratelimit.TooMany(w, retry)
		return true
	}
	return false
}

func decodeBody(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<16)
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "request body must be valid JSON")
		return false
	}
	return true
}

func serverError(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}

func (h *handler) register(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"display_name"`
		Adult       bool   `json:"adult"`
		PowToken    string `json:"pow_challenge"` // from GET /auth/pow-challenge
		Pow         string `json:"pow"`           // nonce solving it
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if !in.Adult {
		httpx.Error(w, http.StatusBadRequest, "adult_required", "you must confirm that you are 18 or older")
		return
	}
	email := normalizeEmail(in.Email)
	if !ValidEmail(email) {
		httpx.Error(w, http.StatusBadRequest, "invalid_email", "email address is invalid")
		return
	}
	if utf8.RuneCountInString(in.Password) < 10 || len(in.Password) > 72 {
		httpx.Error(w, http.StatusBadRequest, "invalid_password", "password must be 10 to 72 bytes long")
		return
	}
	name, ok := ValidDisplayName(in.DisplayName)
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display name must be 1 to 80 characters without @")
		return
	}
	// Verify proof-of-work if configured
	if h.pow != nil {
		if in.PowToken == "" || in.Pow == "" {
			httpx.Error(w, http.StatusBadRequest, "pow_required", "proof-of-work solution required")
			return
		}
		if err := h.pow.Check(in.PowToken, in.Pow); err != nil {
			httpx.Error(w, http.StatusBadRequest, "pow_invalid", "invalid or expired proof-of-work solution")
			return
		}
	}
	// Check password against HIBP (non-blocking on network errors)
	if h.hibp != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if breached, err := h.hibp.IsBreached(ctx, in.Password); err == nil && breached {
			httpx.Error(w, http.StatusBadRequest, "password_breached", "this password has appeared in a data breach; please choose a different one")
			return
		}
	}
	s, err := h.svc.register(r.Context(), email, in.Password, name)
	switch {
	case errors.Is(err, errEmailTaken):
		httpx.Error(w, http.StatusConflict, "email_taken", "email is already registered")
	case errors.Is(err, errNameTaken):
		httpx.Error(w, http.StatusConflict, "display_name_taken", "this name is already taken")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusCreated, s)
	}
}

func (h *handler) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Login    string `json:"login"` // email or display name
		Email    string `json:"email"` // older apps send only this
		Password string `json:"password"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	login := in.Login
	if strings.TrimSpace(login) == "" {
		login = in.Email
	}
	key := h.svc.failureKey(r.Context(), login)
	if h.passwordBlocked(w, key) {
		return
	}
	s, err := h.svc.login(r.Context(), login, in.Password)
	switch {
	case errors.Is(err, errBadCredentials):
		if key != "" {
			h.failures.Allow(key)
		}
		httpx.Error(w, http.StatusUnauthorized, "invalid_credentials", "invalid login or password")
	case errors.Is(err, errBanned):
		httpx.Error(w, http.StatusForbidden, "account_banned", "this account is banned")
	case errors.Is(err, errNotVerified):
		httpx.Error(w, http.StatusForbidden, "email_not_verified", "open the link in the verification mail first")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, s)
	}
}

func (h *handler) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	s, err := h.svc.refresh(r.Context(), in.RefreshToken)
	switch {
	case errors.Is(err, errBadRefresh):
		httpx.Error(w, http.StatusUnauthorized, "invalid_refresh_token", "refresh token is invalid, expired or already used")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, s)
	}
}

func (h *handler) me(w http.ResponseWriter, r *http.Request) {
	id, _ := UserID(r.Context())
	u, err := h.svc.user(r.Context(), id)
	if err != nil {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
		return
	}
	out := struct {
		*User
		UnreadActivity int `json:"unread_activity"`
	}{User: u}
	if h.unreadActivity != nil {
		if out.UnreadActivity, err = h.unreadActivity(r.Context(), id); err != nil {
			serverError(w)
			return
		}
	}
	httpx.JSON(w, http.StatusOK, out)
}

func (h *handler) verifyEmail(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token string `json:"token"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.Token == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_token", "verification token is required")
		return
	}
	// Only the hash is stored; the lookup by it is an index read.
	res, err := h.svc.db.ExecContext(r.Context(),
		`UPDATE users SET email_verified = 1, email_verify_hash = NULL, email_verify_expires = NULL
		 WHERE email_verify_hash = ? AND email_verify_expires > NOW()`, hashToken(in.Token))
	if err != nil {
		serverError(w)
		return
	}
	if n, _ := res.RowsAffected(); n != 1 {
		httpx.Error(w, http.StatusBadRequest, "invalid_token", "verification token is invalid or expired")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// forgotPassword mails a reset link. It answers 204 whether or not the
// address has an account (and also when that address already got its
// ForgotPasswordEmail share of mails), so it reveals nothing; the per-IP
// ForgotPassword limit sits in front of it.
func (h *handler) forgotPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	email := normalizeEmail(in.Email)
	if !ValidEmail(email) {
		httpx.Error(w, http.StatusBadRequest, "invalid_email", "email address is invalid")
		return
	}
	if ok, _ := h.forgotPerEmail.Allow("email:" + email); ok && h.svc.mailOn() {
		h.svc.background(func(ctx context.Context) { h.svc.sendPasswordResetEmail(ctx, email) })
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handler) resetPassword(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token       string `json:"token"`
		NewPassword string `json:"new_password"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	if in.Token == "" {
		httpx.Error(w, http.StatusBadRequest, "missing_token", "reset token is required")
		return
	}
	if utf8.RuneCountInString(in.NewPassword) < 10 || len(in.NewPassword) > 72 {
		httpx.Error(w, http.StatusBadRequest, "invalid_password", "password must be 10 to 72 bytes long")
		return
	}
	// The token first: without a valid one nobody gets to use this endpoint
	// as a free HIBP lookup.
	tokenHash := hashToken(in.Token)
	var id uint64
	err := h.svc.db.QueryRowContext(r.Context(),
		`SELECT id FROM users WHERE password_reset_hash = ? AND password_reset_expires > NOW()`, tokenHash).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusBadRequest, "invalid_token", "reset token is invalid or expired")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	if h.hibp != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if breached, err := h.hibp.IsBreached(ctx, in.NewPassword); err == nil && breached {
			httpx.Error(w, http.StatusBadRequest, "password_breached", "this password has appeared in a data breach; please choose a different one")
			return
		}
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.NewPassword), bcryptCost)
	if err != nil {
		serverError(w)
		return
	}
	// The mail reached its owner, so the address counts as verified too.
	// Matching the hash again makes the token single-use under concurrency.
	res, err := h.svc.db.ExecContext(r.Context(),
		`UPDATE users SET password_hash = ?, password_reset_hash = NULL, password_reset_expires = NULL,
		   email_verified = 1, email_verify_hash = NULL, email_verify_expires = NULL
		 WHERE id = ? AND password_reset_hash = ?`, string(hash), id, tokenHash)
	if err != nil {
		serverError(w)
		return
	}
	if n, _ := res.RowsAffected(); n != 1 {
		httpx.Error(w, http.StatusBadRequest, "invalid_token", "reset token is invalid or expired")
		return
	}
	// Revoke all refresh tokens (log out everywhere)
	_, err = h.svc.db.ExecContext(r.Context(),
		`UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL`, id)
	if err != nil {
		serverError(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *handler) powChallenge(w http.ResponseWriter, r *http.Request) {
	if h.pow == nil {
		httpx.Error(w, http.StatusNotImplemented, "not_implemented", "proof-of-work not configured")
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]string{"challenge": h.pow.Issue()})
}
