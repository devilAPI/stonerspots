package admin

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/photos"
	"stonerspots/backend/internal/totp"
)

type handler struct {
	repo   repo
	photos photos.Storage

	// updateDir and versionFile: see system.go
	updateDir   string
	versionFile string
}

const (
	defaultLimit = 20
	maxLimit     = 100
)

type cursorPayload struct {
	ID uint64 `json:"id"`
}

func encodeCursor(id uint64) string {
	b, _ := json.Marshal(cursorPayload{ID: id})
	return base64.RawURLEncoding.EncodeToString(b)
}

func decodeCursor(s string) (uint64, bool) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, false
	}
	var p struct {
		ID *uint64 `json:"id"`
	}
	if json.Unmarshal(b, &p) != nil || p.ID == nil {
		return 0, false
	}
	return *p.ID, true
}

// page parses limit and cursor; it writes the 400 itself when invalid.
// A cursor of 0 means "first page".
func page(w http.ResponseWriter, r *http.Request) (limit int, after uint64, ok bool) {
	limit = defaultLimit
	if s := r.URL.Query().Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 || n > maxLimit {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be between 1 and 100")
			return 0, 0, false
		}
		limit = n
	}
	if s := r.URL.Query().Get("cursor"); s != "" {
		id, good := decodeCursor(s)
		if !good || id == 0 {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "cursor is malformed")
			return 0, 0, false
		}
		after = id
	}
	return limit, after, true
}

// respond trims the limit+1 lookahead row and writes {"items", "next_cursor"}.
func respond[T any](w http.ResponseWriter, items []T, limit int, id func(T) uint64) {
	if items == nil {
		items = []T{}
	}
	var next *string
	if len(items) > limit {
		items = items[:limit]
		c := encodeCursor(id(items[limit-1]))
		next = &c
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

func serverError(w http.ResponseWriter) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}

func (h handler) reports(w http.ResponseWriter, r *http.Request) {
	limit, after, ok := page(w, r)
	if !ok {
		return
	}
	items, err := h.repo.reports(r.Context(), limit+1, after)
	if err != nil {
		serverError(w)
		return
	}
	respond(w, items, limit, func(i reportItem) uint64 { return i.ID })
}

func (h handler) users(w http.ResponseWriter, r *http.Request) {
	limit, after, ok := page(w, r)
	if !ok {
		return
	}
	items, err := h.repo.users(r.Context(), r.URL.Query().Get("q"), limit+1, after)
	if err != nil {
		serverError(w)
		return
	}
	respond(w, items, limit, func(i userItem) uint64 { return i.ID })
}

func (h handler) spots(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if status != "" && status != "active" && status != "hidden" {
		httpx.Error(w, http.StatusBadRequest, "invalid_status", "status must be active or hidden")
		return
	}
	limit, after, ok := page(w, r)
	if !ok {
		return
	}
	items, err := h.repo.spots(r.Context(), r.URL.Query().Get("q"), status, limit+1, after)
	if err != nil {
		serverError(w)
		return
	}
	respond(w, items, limit, func(i spotItem) uint64 { return i.ID })
}

func (h handler) deleteSpot(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	switch err := h.repo.deleteSpot(r.Context(), id); {
	case errors.Is(err, errNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

// ---- TOTP 2FA for admins ----

type totpStatus struct {
	Enabled bool `json:"enabled"`
}

func (h handler) totpStatus(w http.ResponseWriter, r *http.Request) {
	id, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
		return
	}
	var enabled bool
	var secret sql.NullString
	err := h.repo.db.QueryRowContext(r.Context(), `SELECT totp_enabled, totp_secret FROM users WHERE id = ?`, id).Scan(&enabled, &secret)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusOK, totpStatus{Enabled: enabled})
}

type totpEnableStart struct {
	Secret string `json:"secret"`
	URI    string `json:"uri"`
}

func (h handler) totpEnableStart(w http.ResponseWriter, r *http.Request) {
	id, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
		return
	}
	var enabled bool
	err := h.repo.db.QueryRowContext(r.Context(), `SELECT totp_enabled FROM users WHERE id = ?`, id).Scan(&enabled)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "unknown user")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	if enabled {
		httpx.Error(w, http.StatusBadRequest, "already_enabled", "2FA is already enabled")
		return
	}
	secret, err := totp.GenerateSecret()
	if err != nil {
		serverError(w)
		return
	}
	// Store secret temporarily (not enabled yet)
	if _, err := h.repo.db.ExecContext(r.Context(), `UPDATE users SET totp_secret = ? WHERE id = ?`, secret, id); err != nil {
		serverError(w)
		return
	}
	uri := totp.ProvisioningURI(secret, "admin@"+r.Host, "Stonerspots")
	httpx.JSON(w, http.StatusOK, totpEnableStart{Secret: secret, URI: uri})
}

type totpVerifyReq struct {
	Code string `json:"code"`
}

func (h handler) totpVerify(w http.ResponseWriter, r *http.Request) {
	id, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
		return
	}
	var in totpVerifyReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	if len(in.Code) != 6 {
		httpx.Error(w, http.StatusBadRequest, "invalid_code", "code must be 6 digits")
		return
	}
	var secret sql.NullString
	err := h.repo.db.QueryRowContext(r.Context(), `SELECT totp_secret FROM users WHERE id = ?`, id).Scan(&secret)
	if errors.Is(err, sql.ErrNoRows) || !secret.Valid {
		httpx.Error(w, http.StatusBadRequest, "no_secret", "2FA enrollment not started")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	if !totp.Validate(secret.String, in.Code) {
		httpx.Error(w, http.StatusBadRequest, "invalid_code", "invalid or expired code")
		return
	}
	// Enable 2FA
	if _, err := h.repo.db.ExecContext(r.Context(), `UPDATE users SET totp_enabled = 1 WHERE id = ?`, id); err != nil {
		serverError(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type totpDisableReq struct {
	Password string `json:"password"`
	Code     string `json:"code"`
}

func (h handler) totpDisable(w http.ResponseWriter, r *http.Request) {
	id, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "missing bearer token")
		return
	}
	var in totpDisableReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	if len(in.Code) != 6 {
		httpx.Error(w, http.StatusBadRequest, "invalid_code", "code must be 6 digits")
		return
	}
	var secret sql.NullString
	var hash string
	err := h.repo.db.QueryRowContext(r.Context(), `SELECT totp_secret, password_hash FROM users WHERE id = ?`, id).Scan(&secret, &hash)
	if errors.Is(err, sql.ErrNoRows) || !secret.Valid {
		httpx.Error(w, http.StatusBadRequest, "not_enabled", "2FA is not enabled")
		return
	}
	if err != nil {
		serverError(w)
		return
	}
	if !totp.Validate(secret.String, in.Code) {
		httpx.Error(w, http.StatusBadRequest, "invalid_code", "invalid or expired code")
		return
	}
	// Disable 2FA (password was already verified by RequireAdmin middleware)
	if _, err := h.repo.db.ExecContext(r.Context(), `UPDATE users SET totp_enabled = 0, totp_secret = NULL WHERE id = ?`, id); err != nil {
		serverError(w)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---- photo moderation ----

type photoItem struct {
	ID        uint64    `json:"id"`
	UserID    uint64    `json:"user_id"`
	Key       string    `json:"key"`
	ThumbKey  string    `json:"thumb_key"`
	Width     int       `json:"width"`
	Height    int       `json:"height"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

func (h handler) listPhotos(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	if status != "" && status != "pending" && status != "approved" && status != "rejected" {
		httpx.Error(w, http.StatusBadRequest, "invalid_status", "status must be pending, approved, or rejected")
		return
	}
	limit := 50
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 200 {
			limit = n
		}
	}
	q := "SELECT id, user_id, `key`, thumb_key, width, height, status, created_at FROM photos"
	args := []any{}
	if status != "" {
		q += ` WHERE status = ?`
		args = append(args, status)
	}
	q += ` ORDER BY created_at DESC LIMIT ?`
	args = append(args, limit)
	rows, err := h.repo.db.QueryContext(r.Context(), q, args...)
	if err != nil {
		serverError(w)
		return
	}
	defer rows.Close()
	var out []photoItem
	for rows.Next() {
		var p photoItem
		if err := rows.Scan(&p.ID, &p.UserID, &p.Key, &p.ThumbKey, &p.Width, &p.Height, &p.Status, &p.CreatedAt); err != nil {
			serverError(w)
			return
		}
		p.CreatedAt = p.CreatedAt.UTC()
		out = append(out, p)
	}
	if err := rows.Err(); err != nil {
		serverError(w)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": out})
}

type photoPatch struct {
	Status *string `json:"status"`
}

func (h handler) patchPhoto(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "not_found", "photo not found")
		return
	}
	var in photoPatch
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<10)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	if in.Status == nil || (*in.Status != "approved" && *in.Status != "rejected") {
		httpx.Error(w, http.StatusBadRequest, "invalid_status", "status must be approved or rejected")
		return
	}
	res, err := h.repo.db.ExecContext(r.Context(), `UPDATE photos SET status = ? WHERE id = ?`, *in.Status, id)
	if err != nil {
		serverError(w)
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		httpx.Error(w, http.StatusNotFound, "not_found", "photo not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// rotatePhoto turns a photo clockwise: {"degrees": 90 | 180 | 270}. It
// answers the photo's new URLs, which change with every rotation.
func (h handler) rotatePhoto(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "photo")
		return
	}
	p, ok := readPatch(w, r, "degrees")
	if !ok {
		return
	}
	var degrees int
	if _, good := field(p, "degrees", &degrees); !good {
		badBody(w)
		return
	}
	res, err := photos.Rotate(r.Context(), h.repo.db, h.photos, id, degrees)
	switch {
	case errors.Is(err, photos.ErrNotFound):
		notFound(w, "photo")
	case errors.Is(err, photos.ErrInvalidRotation):
		httpx.Error(w, http.StatusBadRequest, "invalid_rotation", "degrees must be 90, 180 or 270")
	case err != nil:
		serverError(w)
	default:
		httpx.JSON(w, http.StatusOK, res)
	}
}

// deletePhoto removes a photo with its files.
func (h handler) deletePhoto(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(r)
	if !ok {
		notFound(w, "photo")
		return
	}
	switch err := photos.Remove(r.Context(), h.repo.db, h.photos, id); {
	case errors.Is(err, photos.ErrNotFound):
		notFound(w, "photo")
	case errors.Is(err, photos.ErrLastPhoto):
		httpx.Error(w, http.StatusConflict, "last_photo", "the update has no text; delete the update instead of its last photo")
	case err != nil:
		serverError(w)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
