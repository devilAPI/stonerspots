package spots

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/spots/tagset"
)

// Mount registers spot routes with full paths on the /api/v1 router.
func Mount(r chi.Router, d app.Deps, quota *quotas.Tracker) {
	h := &handler{
		repo:  &Repo{DB: d.DB, PublicBaseURL: strings.TrimRight(d.Cfg.PublicBaseURL, "/")},
		quota: quota,
	}
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Post("/spots", h.create)
	r.Get("/spots/nearby", h.nearby)
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Put("/spots/{id}/tags", h.putTags)
	r.Get("/spots/{id}", h.get)
	r.Get("/spots", h.list)
	r.Get("/tags", h.tags)
}

// spotLocked is the answer to a non-admin changing a locked spot.
func spotLocked(w http.ResponseWriter) {
	httpx.Error(w, http.StatusForbidden, "spot_locked", "this spot is locked; only admins can change it")
}

// tags lists the tag catalog (key, German and English name, icon) in order.
func (h *handler) tags(w http.ResponseWriter, r *http.Request) {
	list, err := tagset.List(r.Context(), h.repo.DB)
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

type handler struct {
	repo  *Repo
	quota *quotas.Tracker
}

type createReq struct {
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Lat         *float64 `json:"lat"`
	Lon         *float64 `json:"lon"`
	Force       bool     `json:"force"`
	PhotoIDs    []uint64 `json:"photo_ids"`
	Tags        []string `json:"tags"`
}

// tagsError writes the response for a failed tag validation: 400 for unknown
// tags (see GET /tags), 500 for a database error.
func tagsError(w http.ResponseWriter, err error) {
	if errors.Is(err, tagset.ErrInvalid) {
		httpx.Error(w, http.StatusBadRequest, "invalid_tags", "tags must be distinct entries of the tag catalog (GET /tags)")
		return
	}
	internal(w, err)
}

// tagsParam parses the ?tags= filter, writing the error itself on failure.
func (h *handler) tagsParam(w http.ResponseWriter, r *http.Request) ([]string, bool) {
	tags, err := tagset.ParseParam(r.Context(), h.repo.DB, r.URL.Query().Get("tags"))
	if err != nil {
		tagsError(w, err)
		return nil, false
	}
	return tags, true
}

func (h *handler) putTags(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	var req struct {
		Tags []string `json:"tags"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body is not valid JSON")
		return
	}
	owner, locked, err := h.repo.OwnerAndLock(r.Context(), id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	if err != nil {
		internal(w, err)
		return
	}
	if owner != uid || locked {
		isAdmin, err := h.repo.IsAdmin(r.Context(), uid)
		if err != nil {
			internal(w, err)
			return
		}
		switch {
		case isAdmin:
		case owner != uid:
			httpx.Error(w, http.StatusForbidden, "forbidden", "only the author or an admin can change tags")
			return
		default:
			spotLocked(w)
			return
		}
	}
	tags, err := NormalizeTags(r.Context(), h.repo.DB, req.Tags)
	if err != nil {
		tagsError(w, err)
		return
	}
	if err := h.repo.SetTags(r.Context(), id, tags); err != nil {
		internal(w, err)
		return
	}
	s, err := h.repo.Get(r.Context(), id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, s)
}

// ValidCoord reports whether lat/lon are valid degrees.
func ValidCoord(lat, lon float64) bool { return validCoord(lat, lon) }

// InRegion reports whether lat/lon lie inside the supported DACH box.
func InRegion(lat, lon float64) bool { return inRegion(lat, lon) }

func validCoord(lat, lon float64) bool {
	return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

func inRegion(lat, lon float64) bool {
	return lat >= regionSouth && lat <= regionNorth && lon >= regionWest && lon <= regionEast
}

func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "login required")
		return
	}
	if h.quota != nil && !h.quota.Allow(uid, quotas.Spots) {
		httpx.Error(w, http.StatusTooManyRequests, "quota_exceeded", "daily spot creation limit reached")
		return
	}
	var req createReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&req); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body is not valid JSON")
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	if n := utf8.RuneCountInString(req.Title); n < 3 || n > 80 {
		httpx.Error(w, http.StatusBadRequest, "invalid_title", "title must be 3-80 characters")
		return
	}
	if utf8.RuneCountInString(req.Description) > 1000 {
		httpx.Error(w, http.StatusBadRequest, "invalid_description", "description must be at most 1000 characters")
		return
	}
	if req.Lat == nil || req.Lon == nil || !validCoord(*req.Lat, *req.Lon) {
		httpx.Error(w, http.StatusBadRequest, "invalid_location", "lat must be in -90..90 and lon in -180..180")
		return
	}
	tags, err := NormalizeTags(r.Context(), h.repo.DB, req.Tags)
	if err != nil {
		tagsError(w, err)
		return
	}
	lat, lon := *req.Lat, *req.Lon
	if !inRegion(lat, lon) {
		httpx.Error(w, http.StatusBadRequest, "invalid_location", "location is outside the supported region (DACH); check that lat and lon are not swapped")
		return
	}
	if !req.Force {
		dup, err := h.repo.FindWithin(r.Context(), lat, lon, duplicateMeters)
		if err != nil {
			internal(w, err)
			return
		}
		if dup != nil {
			httpx.JSON(w, http.StatusConflict, map[string]any{
				"error": map[string]any{
					"code":    "possible_duplicate",
					"message": "a spot already exists within 25 m; resend with force=true to create anyway",
				},
				"existing_id": dup.ID,
			})
			return
		}
	}
	id, err := h.repo.Create(r.Context(), Spot{Title: req.Title, Description: req.Description, Lat: lat, Lon: lon, Tags: tags}, uid)
	if err != nil {
		internal(w, err)
		return
	}
	// The description and photos become the spot's first feed update.
	if body := strings.TrimSpace(req.Description); body != "" || len(req.PhotoIDs) > 0 {
		if _, err := feed.CreateUpdate(r.Context(), h.repo.DB, uid, id, body, req.PhotoIDs); err != nil {
			_, _ = h.repo.DB.ExecContext(r.Context(), "DELETE FROM spots WHERE id = ?", id)
			if errors.Is(err, feed.ErrInvalidPhoto) {
				httpx.Error(w, http.StatusBadRequest, "invalid_photo", "photo is missing, not yours, or already used")
				return
			}
			internal(w, err)
			return
		}
	}
	s, err := h.repo.Get(r.Context(), id)
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusCreated, s)
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	s, err := h.repo.Get(r.Context(), id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, s)
}

func floatParam(r *http.Request, name string) (float64, bool) {
	v, err := strconv.ParseFloat(r.URL.Query().Get(name), 64)
	if err != nil || v != v || v > 1e9 || v < -1e9 {
		return 0, false
	}
	return v, true
}

func limitParam(r *http.Request) (int, bool) {
	s := r.URL.Query().Get("limit")
	if s == "" {
		return defaultLimit, true
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, false
	}
	return clampLimit(n), true
}

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	var b BBox
	var ok1, ok2, ok3, ok4 bool
	b.South, ok1 = floatParam(r, "south")
	b.West, ok2 = floatParam(r, "west")
	b.North, ok3 = floatParam(r, "north")
	b.East, ok4 = floatParam(r, "east")
	if !(ok1 && ok2 && ok3 && ok4) {
		httpx.Error(w, http.StatusBadRequest, "invalid_bbox", "south, west, north and east are required numbers")
		return
	}
	if b.South > b.North || b.West > b.East {
		httpx.Error(w, http.StatusBadRequest, "invalid_bbox", "bounding box is inverted (south > north or west > east)")
		return
	}
	// Clamp a world-sized box to valid coordinates.
	b.South, b.North = clamp(b.South, -90, 90), clamp(b.North, -90, 90)
	b.West, b.East = clamp(b.West, -180, 180), clamp(b.East, -180, 180)
	limit, ok := limitParam(r)
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be an integer")
		return
	}
	tags, ok := h.tagsParam(w, r)
	if !ok {
		return
	}
	list, err := h.repo.InBBox(r.Context(), b, Filter{Limit: limit, Tags: tags})
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func (h *handler) nearby(w http.ResponseWriter, r *http.Request) {
	lat, ok1 := floatParam(r, "lat")
	lon, ok2 := floatParam(r, "lon")
	if !ok1 || !ok2 || !validCoord(lat, lon) {
		httpx.Error(w, http.StatusBadRequest, "invalid_location", "lat must be in -90..90 and lon in -180..180")
		return
	}
	radius := 5000
	if s := r.URL.Query().Get("radius_m"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n <= 0 {
			httpx.Error(w, http.StatusBadRequest, "invalid_radius", "radius_m must be a positive integer")
			return
		}
		radius = n
	}
	if radius > maxNearbyRadius {
		radius = maxNearbyRadius
	}
	limit, ok := limitParam(r)
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be an integer")
		return
	}
	tags, ok := h.tagsParam(w, r)
	if !ok {
		return
	}
	list, err := h.repo.Nearby(r.Context(), lat, lon, radius, limit, tags)
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}

func clamp(v, lo, hi float64) float64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func internal(w http.ResponseWriter, err error) {
	httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
}
