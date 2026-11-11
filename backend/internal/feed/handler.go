package feed

import (
	"database/sql"
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/spots/tagset"
)

type handler struct {
	db        *sql.DB
	base      string
	uploadDir string
	quota     *quotas.Tracker
	guard     *auth.Guard
}

// asAdmin runs op as the caller; when that fails with ErrSpotLocked and the
// caller is an admin who passes the 2FA check, it runs op again with admin
// rights. handled: an error answer was written already.
func (h *handler) asAdmin(w http.ResponseWriter, r *http.Request, op func(admin bool) error) (err error, handled bool) {
	err = op(false)
	if !errors.Is(err, ErrSpotLocked) {
		return err, false
	}
	admin, handled := h.guard.AdminPowers(w, r)
	if handled || !admin {
		return err, handled
	}
	return op(true), false
}

func (h *handler) postUpdate(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	if h.quota != nil && !h.quota.Allow(uid, quotas.Updates) {
		httpx.Error(w, http.StatusTooManyRequests, "quota_exceeded", "daily update limit reached")
		return
	}
	spotID, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	}
	var in struct {
		Body     string   `json:"body"`
		Tag      string   `json:"tag"`
		PhotoIDs []uint64 `json:"photo_ids"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&in); err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_json", "request body must be valid JSON")
		return
	}
	var id uint64
	err, handled := h.asAdmin(w, r, func(admin bool) (err error) {
		id, err = createUpdate(r.Context(), h.db, uid, spotID, in.Body, in.Tag, in.PhotoIDs, admin)
		return err
	})
	if handled {
		return
	}
	switch {
	case errors.Is(err, ErrInvalidTag):
		httpx.Error(w, http.StatusBadRequest, "invalid_tag", "tag must be one of note, still_good, crowded, dirty, closed")
		return
	case errors.Is(err, ErrInvalidPhoto):
		httpx.Error(w, http.StatusBadRequest, "invalid_photo", "photos must be your own, unattached, unique and at most 4")
		return
	case errors.Is(err, ErrInvalidBody):
		httpx.Error(w, http.StatusBadRequest, "invalid_body", "body must be at most 2000 characters; text or photos required")
		return
	case errors.Is(err, ErrSpotNotFound):
		httpx.Error(w, http.StatusNotFound, "not_found", "spot not found")
		return
	case errors.Is(err, ErrSpotLocked):
		spotLocked(w)
		return
	case err != nil:
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	it, err := getItem(r.Context(), h.db, h.base, id)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	httpx.JSON(w, http.StatusCreated, it)
}

// maxRadiusKm is half the earth's circumference: every spot.
const maxRadiusKm = 20000

func (h *handler) getFeed(w http.ResponseWriter, r *http.Request) {
	p := r.URL.Query()
	q := query{sort: sortNew, limit: 20}
	switch p.Get("sort") {
	case "", "new":
	case "top":
		q.sort = sortTop
	case "nearby":
		q.sort = sortNearby
	default:
		httpx.Error(w, http.StatusBadRequest, "invalid_sort", "sort must be new, top or nearby")
		return
	}
	tags, err := tagset.ParseParam(r.Context(), h.db, p.Get("tags"))
	if errors.Is(err, tagset.ErrInvalid) {
		httpx.Error(w, http.StatusBadRequest, "invalid_tags", "tags must be a comma separated list of tag catalog entries (GET /tags)")
		return
	}
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	q.tags = tags
	switch p.Get("following") {
	case "", "false", "0":
	case "true", "1":
		uid, ok := auth.UserID(r.Context())
		if !ok {
			httpx.Error(w, http.StatusUnauthorized, "unauthorized", "following=true requires login")
			return
		}
		q.followerID = uid
	default:
		httpx.Error(w, http.StatusBadRequest, "invalid_following", "following must be true or false")
		return
	}
	if sid := p.Get("spot_id"); sid != "" {
		n, err := strconv.ParseUint(sid, 10, 64)
		if err != nil || n == 0 {
			httpx.Error(w, http.StatusBadRequest, "invalid_spot_id", "spot_id must be a positive integer")
			return
		}
		q.spotID = n
	}
	if l := p.Get("limit"); l != "" {
		n, err := strconv.Atoi(l)
		if err != nil || n < 1 {
			httpx.Error(w, http.StatusBadRequest, "invalid_limit", "limit must be a positive integer")
			return
		}
		q.limit = min(n, 50)
	}
	if rk := p.Get("radius_km"); rk != "" {
		km, err := strconv.ParseFloat(rk, 64)
		if err != nil || math.IsNaN(km) || km <= 0 || km > maxRadiusKm {
			httpx.Error(w, http.StatusBadRequest, "invalid_radius", "radius_km must be between 0 and 20000 (km)")
			return
		}
		q.radius = km * 1000
	}
	if q.sort == sortNearby || q.radius > 0 {
		lat, e1 := strconv.ParseFloat(p.Get("lat"), 64)
		lon, e2 := strconv.ParseFloat(p.Get("lon"), 64)
		if e1 != nil || e2 != nil || math.IsNaN(lat) || math.IsNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180 {
			httpx.Error(w, http.StatusBadRequest, "invalid_location", "sort=nearby and radius_km require valid lat and lon")
			return
		}
		q.lat, q.lon = lat, lon
	}
	if c := p.Get("cursor"); c != "" {
		k, id, err := DecodeCursor(c)
		if err != nil {
			httpx.Error(w, http.StatusBadRequest, "invalid_cursor", "malformed cursor")
			return
		}
		q.hasCur, q.curKey, q.curID = true, k, id
	}
	items, next, err := list(r.Context(), h.db, h.base, q)
	if err != nil {
		httpx.Error(w, http.StatusInternalServerError, "internal", "internal error")
		return
	}
	httpx.JSON(w, http.StatusOK, struct {
		Items      []FeedItem `json:"items"`
		NextCursor *string    `json:"next_cursor"`
	}{items, next})
}
