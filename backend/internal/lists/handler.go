// Package lists implements saved spots: a user's private lists, one of which
// is the default list (Favourites). Lists are never visible to anyone else,
// so a list of another user answers exactly like one that does not exist.
package lists

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/spots"
)

const (
	// MaxLists is how many lists a user can have besides Favourites.
	MaxLists = 50

	maxNameLen   = 60
	defaultLimit = 20
	maxLimit     = 50

	// defaultAlias stands for the Favourites list in item routes, so a spot
	// can be saved without knowing that list's id, or whether it exists yet.
	defaultAlias = "default"
)

// reservedNames would look like the default list once translated.
var reservedNames = map[string]bool{"favourites": true, "favorites": true, "favoriten": true}

// Mount registers list routes with full paths on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) {
	h := &handler{repo: repo{
		db:    d.DB,
		base:  d.Cfg.PublicBaseURL,
		spots: &spots.Repo{DB: d.DB, PublicBaseURL: d.Cfg.PublicBaseURL},
	}}
	authed := r.With(auth.Middleware(d.Cfg.JWTSecret))
	authed.Get("/lists", h.list)
	authed.Post("/lists", h.create)
	authed.Get("/lists/{id}", h.get)
	authed.Patch("/lists/{id}", h.rename)
	authed.Delete("/lists/{id}", h.delete)
	authed.Get("/lists/{id}/spots", h.spots)
	authed.Put("/lists/{id}/spots/{spotID}", h.addSpot)
	authed.Delete("/lists/{id}/spots/{spotID}", h.removeSpot)
	authed.Get("/spots/{id}/lists", h.membership)
}

type handler struct{ repo repo }

func fail(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errListNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "list not found")
	case errors.Is(err, errSpotNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
	case errors.Is(err, errDefaultList):
		httpx.Error(w, http.StatusForbidden, "default_list", "the default list cannot be renamed or deleted")
	case errors.Is(err, errNameTaken):
		httpx.Error(w, http.StatusConflict, "name_taken", "you already have a list with this name")
	case errors.Is(err, errListLimit):
		httpx.Error(w, http.StatusConflict, "list_limit", "too many lists")
	case errors.Is(err, errNoUser):
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
	default:
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
	}
}

func user(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
	}
	return uid, ok
}

func parseID(s string) (uint64, bool) {
	id, err := strconv.ParseUint(s, 10, 64)
	return id, err == nil && id > 0
}

func listID(w http.ResponseWriter, r *http.Request) (uint64, bool) {
	id, ok := parseID(chi.URLParam(r, "id"))
	if !ok {
		fail(w, errListNotFound)
	}
	return id, ok
}

// cleanName trims a list name and reports whether it may be used.
func cleanName(s string) (string, bool) {
	s = strings.TrimSpace(s)
	n := utf8.RuneCountInString(s)
	return s, n >= 1 && n <= maxNameLen && !strings.ContainsFunc(s, unicode.IsControl)
}

// readName parses and validates the request body of create and rename.
func readName(w http.ResponseWriter, r *http.Request) (string, bool) {
	var in struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<12)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return "", false
	}
	name, ok := cleanName(in.Name)
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_name", "name must be 1-60 characters")
		return "", false
	}
	if reservedNames[strings.ToLower(name)] {
		fail(w, errNameTaken)
		return "", false
	}
	return name, true
}

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	items, err := h.repo.all(r.Context(), uid)
	if err != nil {
		fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items})
}

func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	name, ok := readName(w, r)
	if !ok {
		return
	}
	l, err := h.repo.create(r.Context(), uid, name)
	if err != nil {
		fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, l)
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, ok := listID(w, r)
	if !ok {
		return
	}
	l, err := h.repo.get(r.Context(), uid, id)
	if err != nil {
		fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, l)
}

func (h *handler) rename(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, ok := listID(w, r)
	if !ok {
		return
	}
	// First the list: whether it exists must not depend on the body.
	if err := h.repo.ownEditable(r.Context(), uid, id); err != nil {
		fail(w, err)
		return
	}
	name, ok := readName(w, r)
	if !ok {
		return
	}
	l, err := h.repo.rename(r.Context(), uid, id, name)
	if err != nil {
		fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, l)
}

func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, ok := listID(w, r)
	if !ok {
		return
	}
	if err := h.repo.delete(r.Context(), uid, id); err != nil {
		fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func encodeCursor(id uint64) string {
	return base64.RawURLEncoding.EncodeToString([]byte(strconv.FormatUint(id, 10)))
}

func decodeCursor(s string) (uint64, bool) {
	b, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return 0, false
	}
	return parseID(string(b))
}

func (h *handler) spots(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, ok := listID(w, r)
	if !ok {
		return
	}
	q := r.URL.Query()
	limit := defaultLimit
	if s := q.Get("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be a positive integer")
			return
		}
		limit = min(n, maxLimit)
	}
	var cursor uint64
	if c := q.Get("cursor"); c != "" {
		if cursor, ok = decodeCursor(c); !ok {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
			return
		}
	}
	items, last, err := h.repo.spotsIn(r.Context(), uid, id, cursor, limit)
	if err != nil {
		fail(w, err)
		return
	}
	var next *string
	if last != 0 {
		c := encodeCursor(last)
		next = &c
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"items": items, "next_cursor": next})
}

// itemIDs reads the list and spot of an item route, resolving defaultAlias.
func (h *handler) itemIDs(w http.ResponseWriter, r *http.Request, uid uint64) (uint64, uint64, bool) {
	spotID, ok := parseID(chi.URLParam(r, "spotID"))
	if !ok {
		fail(w, errSpotNotFound)
		return 0, 0, false
	}
	if chi.URLParam(r, "id") == defaultAlias {
		id, err := h.repo.defaultList(r.Context(), uid)
		if err != nil {
			fail(w, err)
			return 0, 0, false
		}
		return id, spotID, true
	}
	id, ok := listID(w, r)
	return id, spotID, ok
}

func (h *handler) respondMembership(w http.ResponseWriter, r *http.Request, uid, spotID uint64) {
	ids, err := h.repo.membership(r.Context(), uid, spotID)
	if err != nil {
		fail(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"list_ids": ids})
}

func (h *handler) addSpot(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, spotID, ok := h.itemIDs(w, r, uid)
	if !ok {
		return
	}
	if err := h.repo.add(r.Context(), uid, id, spotID); err != nil {
		fail(w, err)
		return
	}
	h.respondMembership(w, r, uid, spotID)
}

func (h *handler) removeSpot(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	id, spotID, ok := h.itemIDs(w, r, uid)
	if !ok {
		return
	}
	if err := h.repo.remove(r.Context(), uid, id, spotID); err != nil {
		fail(w, err)
		return
	}
	h.respondMembership(w, r, uid, spotID)
}

func (h *handler) membership(w http.ResponseWriter, r *http.Request) {
	uid, ok := user(w, r)
	if !ok {
		return
	}
	spotID, ok := parseID(chi.URLParam(r, "id"))
	if !ok {
		fail(w, errSpotNotFound)
		return
	}
	if err := h.repo.spotActive(r.Context(), spotID); err != nil {
		fail(w, err)
		return
	}
	h.respondMembership(w, r, uid, spotID)
}
