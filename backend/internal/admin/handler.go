package admin

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/httpx"
)

type handler struct{ repo repo }

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
