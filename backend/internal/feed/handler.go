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
)

type handler struct {
	db        *sql.DB
	base      string
	uploadDir string
}

var categories = map[string]bool{"bench": true, "river": true, "lake": true, "viewpoint": true, "forest": true, "park": true, "other": true}

func (h *handler) postUpdate(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
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
	id, err := CreateUpdateTagged(r.Context(), h.db, uid, spotID, in.Body, in.Tag, in.PhotoIDs)
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
	if c := p.Get("category"); c != "" {
		if !categories[c] {
			httpx.Error(w, http.StatusBadRequest, "invalid_category", "unknown category")
			return
		}
		q.category = c
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
	if q.sort == sortNearby {
		lat, e1 := strconv.ParseFloat(p.Get("lat"), 64)
		lon, e2 := strconv.ParseFloat(p.Get("lon"), 64)
		if e1 != nil || e2 != nil || math.IsNaN(lat) || math.IsNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180 {
			httpx.Error(w, http.StatusBadRequest, "invalid_location", "sort=nearby requires valid lat and lon")
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
