// Package zones serves the no-consumption zone layer: places near which § 5
// KCanG (Germany) forbids consuming cannabis - schools, children's and youth
// facilities, playgrounds, public sports facilities, explicit
// smoking:cannabis=no - and pedestrian zones (7-20 h). The data comes from
// OpenStreetMap: built weekly for all of Germany from an extract
// (Geofabrik) on this server, and through Overpass (several public servers,
// tried in turn, by block of 4 × 4 grid tiles) for what is missing, or for
// everything when the extract is turned off (then a background prefetch
// keeps Germany cached). Tiles are cached in memory and in the zone_tiles
// table. Clients get the places; the 100 m buffer is drawn and checked by
// the app.
package zones

import (
	"context"
	"errors"
	"log"
	"net/http"
	"strconv"
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
	}
	s := NewService(d.Cfg.Zones.OverpassURLs, d.Cfg.PublicBaseURL, st)
	if d.DB != nil && d.Cfg.Zones.Enabled {
		go prune(d)
		switch {
		case d.Cfg.Zones.Extract:
			// all of Germany from the OSM extract; Overpass only for gaps
			s.UseExtract()
			go s.RunExtract(context.Background(), d.Cfg.Zones.ExtractURL, d.Cfg.Zones.ExtractDir)
		case d.Cfg.Zones.Prefetch:
			go s.Prefetch(context.Background(), func(ctx context.Context) []block {
				spots, err := spotLocations(ctx, d.DB)
				if err != nil {
					log.Printf("zones: prefetch: spots: %v", err) // Germany in grid order
				}
				return prefetchOrder(spots)
			})
		}
	}
	mount(r, d, s)
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

// pendingAfter is how long a request waits for tiles that are still being
// fetched upstream; then it gets 503 zones_pending with Retry-After.
var pendingAfter = 20 * time.Second

// pendingRetryAfter is the Retry-After (seconds) of a zones_pending answer.
const pendingRetryAfter = 10

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
	// § 5 KCanG is German law: tiles outside Germany are not fetched, and
	// places outside it are dropped from tiles the border runs through.
	var tiles []Tile
	var partly []bool
	for _, t := range b.tiles() {
		if o := GermanyOverlap(t.Bounds()); o != Outside {
			tiles = append(tiles, t)
			partly = append(partly, o == Partly)
		}
	}
	type result struct {
		zones []Zone
		stale bool
		err   error
	}
	results := make([]result, len(tiles))
	// a cold tile can take minutes upstream: answer "pending" instead of
	// holding the request; the fetch goes on and the next try hits the cache
	wait, cancel := context.WithTimeout(r.Context(), pendingAfter)
	defer cancel()
	var wg sync.WaitGroup
	for i, t := range tiles {
		wg.Go(func() {
			z, stale, err := h.s.Tile(wait, t)
			results[i] = result{z, stale, err}
		})
	}
	wg.Wait()

	out := response{Zones: []Zone{}, Attribution: Attribution}
	seen := map[string]bool{}
	for i, res := range results {
		if res.err != nil {
			if r.Context().Err() != nil {
				return // the client left
			}
			// still being fetched, or waiting for an upstream slot: the
			// client should simply ask again
			if errors.Is(res.err, context.DeadlineExceeded) || errors.Is(res.err, errBusy) {
				w.Header().Set("Retry-After", strconv.Itoa(pendingRetryAfter))
				httpx.Error(w, http.StatusServiceUnavailable, "zones_pending",
					"zone data is being fetched, try again in a few seconds")
				return
			}
			httpx.Error(w, http.StatusServiceUnavailable, "zones_unavailable",
				"zone data is unavailable right now, try again later")
			return
		}
		out.Stale = out.Stale || res.stale
		for _, z := range res.zones {
			if partly[i] && !zoneInGermany(z) {
				continue
			}
			// a place across a tile edge is in both tiles
			if !seen[z.ID] {
				seen[z.ID] = true
				out.Zones = append(out.Zones, z)
			}
		}
	}
	// an hour: the zones are rebuilt weekly, and a copy kept for a day can
	// still show a spot as clear after the rebuild added a zone there
	if !out.Stale {
		w.Header().Set("Cache-Control", "public, max-age=3600")
	}
	httpx.JSON(w, http.StatusOK, out)
}
