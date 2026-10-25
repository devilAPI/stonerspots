package auth

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"time"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"

	"stonerspots/backend/internal/hibp"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/pow"
	"stonerspots/backend/internal/ratelimit"
)

type handler struct {
	svc    *service
	hibp   *hibp.Client
	failures *ratelimit.Limiter
	pow    *pow.Challenge
}

// passwordBlocked writes the 429 and reports true when key has no wrong
// guesses left.
func (h *handler) passwordBlocked(w http.ResponseWriter, key string) bool {
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
		Pow         string `json:"pow"` // Proof-of-work solution
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
	name := in.DisplayName
	if n := utf8.RuneCountInString(name); n < 1 || n > 80 {
		httpx.Error(w, http.StatusBadRequest, "invalid_display_name", "display name must be 1 to 80 characters")
		return
	}
	// Verify proof-of-work if configured
	if h.pow != nil {
		if in.Pow == "" {
			httpx.Error(w, http.StatusBadRequest, "pow_required", "proof-of-work solution required")
			return
		}
		challenge, err := pow.ParseChallenge(h.pow.String())
		if err != nil {
			serverError(w)
			return
		}
		sol := &pow.Solution{Challenge: challenge.String(), Nonce: in.Pow}
		if !challenge.Verify(sol) {
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
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusCreated, s)
	}
}

func (h *handler) login(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !decodeBody(w, r, &in) {
		return
	}
	email := normalizeEmail(in.Email)
	if h.passwordBlocked(w, "email:"+email) {
		return
	}
	s, err := h.svc.login(r.Context(), email, in.Password)
	switch {
	case errors.Is(err, errBadCredentials):
		h.failures.Allow("email:" + email)
		httpx.Error(w, http.StatusUnauthorized, "invalid_credentials", "invalid email or password")
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
	httpx.JSON(w, http.StatusOK, u)
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
	var id uint64
	err := h.svc.db.QueryRowContext(r.Context(),
		`SELECT id FROM users WHERE email_verify_token = ? AND email_verify_expires > NOW()`, in.Token).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusBadRequest, "invalid_token", "verification token is invalid or expired")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	_, err = h.svc.db.ExecContext(r.Context(),
		`UPDATE users SET email_verified = 1, email_verify_token = NULL, email_verify_expires = NULL WHERE id = ?`, id)
	if err != nil {
		serverError(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

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
	// Always return 204 to avoid email enumeration
	// The email is sent asynchronously if the account exists and mail is enabled
	go h.svc.sendPasswordResetEmail(r.Context(), email)
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
	// Check password against HIBP
	if h.hibp != nil {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if breached, err := h.hibp.IsBreached(ctx, in.NewPassword); err == nil && breached {
			httpx.Error(w, http.StatusBadRequest, "password_breached", "this password has appeared in a data breach; please choose a different one")
			return
		}
	}
	var id uint64
	err := h.svc.db.QueryRowContext(r.Context(),
		`SELECT id FROM users WHERE password_reset_token = ? AND password_reset_expires > NOW()`, in.Token).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusBadRequest, "invalid_token", "reset token is invalid or expired")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.NewPassword), bcryptCost)
	if err != nil {
		serverError(w)
		return
	}
	_, err = h.svc.db.ExecContext(r.Context(),
		`UPDATE users SET password_hash = ?, password_reset_token = NULL, password_reset_expires = NULL WHERE id = ?`, string(hash), id)
	if err != nil {
		serverError(w)
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
	// Return a fresh challenge each time
	challenge := pow.NewChallenge("register", 18)
	httpx.JSON(w, http.StatusOK, map[string]string{
		"challenge": challenge.String(),
	})
}
