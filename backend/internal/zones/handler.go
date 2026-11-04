// Package zones serves the no-consumption zone layer: places near which § 5
// KCanG (Germany) forbids consuming cannabis - schools, children's and youth
// facilities, playgrounds, public sports facilities, explicit
// smoking:cannabis=no - and pedestrian zones (7-20 h). The data comes from
// OpenStreetMap through Overpass, fetched by grid tile and cached for a
// week in memory and in the zone_tiles table. Clients get the places; the
// 100 m buffer is drawn and checked by the app.
package zones

import (
	"context"
	"errors"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/ratelimit"
)

// Attribution must accompany the data (ODbL).
const Attribution = "© OpenStreetMap contributors (ODbL)"

// pruneAfter: tiles nobody asked for in this long are deleted on start.
const pruneAfter = 90 * 24 * time.Hour

// Mount registers GET /zones (public, own per-IP limit).
func Mount(r chi.Router, d app.Deps) {
	var st store
	if d.DB != nil {
		st = dbStore{db: d.DB}
		if d.Cfg.Zones.Enabled {
			go prune(d)
		}
	}
	mount(r, d, NewService(d.Cfg.Zones.OverpassURL, d.Cfg.PublicBaseURL, st))
}

func mount(r chi.Router, d app.Deps, s *Service) {
	h := &handler{s: s, enabled: d.Cfg.Zones.Enabled}
	r.With(ratelimit.ByIP(ratelimit.New(d.Cfg.Limits.Zones))).Get("/zones", h.get)
}

func prune(d app.Deps) {
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if _, err := d.DB.ExecContext(ctx, `DELETE FROM zone_tiles WHERE fetched_at < ?`,
		time.Now().Add(-pruneAfter).UTC()); err != nil {
		log.Printf("zones: prune: %v", err)
	}
}

type handler struct {
	s       *Service
	enabled bool
}

type response struct {
	Zones       []Zone `json:"zones"`
	Attribution string `json:"attribution"`
	Stale       bool   `json:"stale"`
}

func (h *handler) get(w http.ResponseWriter, r *http.Request) {
	if !h.enabled {
		httpx.Error(w, http.StatusNotFound, "zones_disabled", "the zone layer is turned off on this server")
		return
	}
	b, err := parseBBox(r.URL.Query())
	if err != nil {
		httpx.Error(w, http.StatusBadRequest, "invalid_bbox", err.Error())
		return
	}
	tiles := b.tiles()
	type result struct {
		zones []Zone
		stale bool
		err   error
	}
	results := make([]result, len(tiles))
	var wg sync.WaitGroup
	for i, t := range tiles {
		wg.Go(func() {
			z, stale, err := h.s.Tile(r.Context(), t)
			results[i] = result{z, stale, err}
		})
	}
	wg.Wait()

	out := response{Zones: []Zone{}, Attribution: Attribution}
	seen := map[string]bool{}
	for _, res := range results {
		if res.err != nil {
			if errors.Is(res.err, context.Canceled) {
				return // the client left
			}
			httpx.Error(w, http.StatusServiceUnavailable, "zones_unavailable",
				"zone data is unavailable right now, try again later")
			return
		}
		out.Stale = out.Stale || res.stale
		for _, z := range res.zones {
			// a place across a tile edge is in both tiles
			if !seen[z.ID] {
				seen[z.ID] = true
				out.Zones = append(out.Zones, z)
			}
		}
	}
	if !out.Stale {
		w.Header().Set("Cache-Control", "public, max-age=86400")
	}
	httpx.JSON(w, http.StatusOK, out)
}
