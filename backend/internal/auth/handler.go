package auth

import (
	"encoding/json"
	"errors"
	"net/http"
	"unicode/utf8"

	"stonerspots/backend/internal/httpx"
)

type handler struct{ svc *service }

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
	s, err := h.svc.login(r.Context(), normalizeEmail(in.Email), in.Password)
	switch {
	case errors.Is(err, errBadCredentials):
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
