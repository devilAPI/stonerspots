package geocode

import (
	"errors"
	"log"
	"net/http"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/auth"
	"stonerspots/backend/internal/httpx"
)

const (
	minQueryLen  = 3
	maxQueryLen  = 200
	userLimit    = 20
	userLimitWin = time.Minute
)

// Mount registers GET /geocode (auth required) on the /api/v1 router.
func Mount(r chi.Router, d app.Deps) { mount(r, d, upstreamGap, maxWait) }

func mount(r chi.Router, d app.Deps, interval, wait time.Duration) {
	h := &handler{c: newClient(d.Cfg.GeocoderURL, interval, wait), users: map[uint64][]time.Time{}}
	r.With(auth.Middleware(d.Cfg.JWTSecret)).Get("/geocode", h.search)
}

type handler struct {
	c *client

	mu    sync.Mutex
	users map[uint64][]time.Time // recent request times per user
}

// allow records a request for uid and reports whether it is within 20/minute.
func (h *handler) allow(uid uint64) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := time.Now()
	cutoff := now.Add(-userLimitWin)
	recent := h.users[uid][:0]
	for _, t := range h.users[uid] {
		if t.After(cutoff) {
			recent = append(recent, t)
		}
	}
	if len(recent) >= userLimit {
		h.users[uid] = recent
		return false
	}
	h.users[uid] = append(recent, now)
	if len(h.users) > 10000 { // drop idle users so the map cannot grow unbounded
		for id, ts := range h.users {
			if len(ts) == 0 || !ts[len(ts)-1].After(cutoff) {
				delete(h.users, id)
			}
		}
	}
	return true
}

func (h *handler) search(w http.ResponseWriter, r *http.Request) {
	uid, ok := auth.UserID(r.Context())
	if !ok {
		httpx.Error(w, http.StatusUnauthorized, "unauthorized", "authentication required")
		return
	}
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if n := utf8.RuneCountInString(q); n < minQueryLen || n > maxQueryLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_query", "q must be 3 to 200 characters")
		return
	}
	if !h.allow(uid) {
		httpx.Error(w, http.StatusTooManyRequests, "rate_limited", "too many searches, try again in a minute")
		return
	}
	res, err := h.c.Search(r.Context(), q)
	switch {
	case errors.Is(err, errBusy):
		httpx.Error(w, http.StatusServiceUnavailable, "geocoder_busy", "geocoder is busy, try again shortly")
		return
	case err != nil:
		log.Printf("geocode: upstream: %v", err)
		httpx.Error(w, http.StatusBadGateway, "geocoder_unavailable", "address search is currently unavailable")
		return
	}
	if res == nil {
		res = []Result{}
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"results": res})
}
