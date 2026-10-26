package transit

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/httpx"
)

// maxSpan caps the box per request (degrees per side): the app asks from
// zoom 13 on, which is about 0.35° wide on a large desktop window.
const maxSpan = 0.5

// Mount registers GET /transit/stops (public, like the map) on the /api/v1
// router.
func Mount(r chi.Router, d app.Deps) { mount(r, d, upstreamGap, maxWait) }

func mount(r chi.Router, d app.Deps, interval, wait time.Duration) {
	h := &handler{c: newClient(d.Cfg.OverpassURL, interval, wait)}
	r.Get("/transit/stops", h.stops)
}

type handler struct{ c *client }

// parseBBox reads "west,south,east,north".
func parseBBox(s string) (BBox, bool) {
	parts := strings.Split(s, ",")
	if len(parts) != 4 {
		return BBox{}, false
	}
	var v [4]float64
	for i, p := range parts {
		f, err := strconv.ParseFloat(strings.TrimSpace(p), 64)
		if err != nil {
			return BBox{}, false
		}
		v[i] = f
	}
	b := BBox{W: v[0], S: v[1], E: v[2], N: v[3]}
	ok := b.S >= -90 && b.N <= 90 && b.W >= -180 && b.E <= 180 && b.S < b.N && b.W < b.E
	return b, ok
}

func (h *handler) stops(w http.ResponseWriter, r *http.Request) {
	b, ok := parseBBox(r.URL.Query().Get("bbox"))
	if !ok {
		httpx.Error(w, http.StatusBadRequest, "invalid_bbox", "bbox must be west,south,east,north")
		return
	}
	if b.N-b.S > maxSpan || b.E-b.W > maxSpan {
		httpx.Error(w, http.StatusBadRequest, "bbox_too_large", "bbox must be at most 0.5° per side")
		return
	}
	stops, err := h.c.Stops(r.Context(), b)
	switch {
	case errors.Is(err, errBusy):
		httpx.Error(w, http.StatusServiceUnavailable, "transit_busy", "stops are busy loading, try again shortly")
		return
	case err != nil:
		log.Printf("transit: upstream: %v", err)
		httpx.Error(w, http.StatusBadGateway, "transit_unavailable", "public transport stops are currently unavailable")
		return
	}
	// stops change rarely; let the browser and app reuse an answer briefly
	w.Header().Set("Cache-Control", "public, max-age=3600")
	httpx.JSON(w, http.StatusOK, map[string]any{"stops": stops})
}
