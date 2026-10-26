// Package transit serves public transport stops (train, U-Bahn, tram, bus,
// ferry) for the map from the Overpass API. Results are cached per grid
// cell and shared by everyone, and upstream queries run one at a time, to
// respect the public Overpass instances' usage policy.
package transit

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	userAgent = "stonerspots/0.1 (+https://github.com/devilAPI/stonerspots)"
	// cellDeg is the cache grid: 0.05° is about 5.5 x 3.5 km in the DACH region.
	cellDeg     = 0.05
	cacheTTL    = 7 * 24 * time.Hour
	cacheMax    = 5000 // cells
	upstreamGap = time.Second
	maxWait     = 10 * time.Second
	// dedupeMeters merges the platforms / directions of one stop.
	dedupeMeters = 150
)

var errBusy = errors.New("transit: upstream busy")

// Stop is one public transport stop as returned to the app.
type Stop struct {
	ID   string  `json:"id"`
	Name string  `json:"name"`
	Kind string  `json:"kind"` // train, subway, tram, bus, ferry
	Lat  float64 `json:"lat"`
	Lon  float64 `json:"lon"`
}

// BBox is a lat/lon box; S < N and W < E.
type BBox struct{ S, W, N, E float64 }

type cell struct{ y, x int }

func cellOf(lat, lon float64) cell {
	return cell{int(math.Floor(lat / cellDeg)), int(math.Floor(lon / cellDeg))}
}

type cacheEntry struct {
	stops   []Stop
	expires time.Time
}

type client struct {
	url      string
	http     *http.Client
	interval time.Duration
	maxWait  time.Duration

	upstream chan struct{} // one Overpass query at a time
	mu       sync.Mutex
	last     time.Time // end of the previous upstream query
	cache    map[cell]cacheEntry
	order    []cell
}

func newClient(overpassURL string, interval, wait time.Duration) *client {
	return &client{
		url:      overpassURL,
		http:     &http.Client{Timeout: 90 * time.Second}, // public instances can take ~45 s
		interval: interval,
		maxWait:  wait,
		upstream: make(chan struct{}, 1),
		cache:    map[cell]cacheEntry{},
	}
}

// cells lists the grid cells covering b.
func cells(b BBox) []cell { return cellRange(cellOf(b.S, b.W), cellOf(b.N, b.E)) }

func cellRange(lo, hi cell) []cell {
	var out []cell
	for y := lo.y; y <= hi.y; y++ {
		for x := lo.x; x <= hi.x; x++ {
			out = append(out, cell{y, x})
		}
	}
	return out
}

// missing returns the cells without a fresh cache entry, and the stops of
// the others.
func (c *client) lookup(cs []cell) (missing []cell, have []Stop) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	for _, k := range cs {
		if e, ok := c.cache[k]; ok && now.Before(e.expires) {
			have = append(have, e.stops...)
		} else {
			missing = append(missing, k)
		}
	}
	return missing, have
}

func (c *client) store(cs []cell, stops []Stop) {
	byCell := map[cell][]Stop{}
	for _, s := range stops {
		k := cellOf(s.Lat, s.Lon)
		byCell[k] = append(byCell[k], s)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	exp := time.Now().Add(cacheTTL)
	for _, k := range cs { // empty cells are cached too
		if _, ok := c.cache[k]; !ok {
			c.order = append(c.order, k)
		}
		c.cache[k] = cacheEntry{stops: byCell[k], expires: exp}
	}
	for len(c.order) > cacheMax {
		delete(c.cache, c.order[0])
		c.order = c.order[1:]
	}
}

// Stops returns the stops inside b, merged per stop.
func (c *client) Stops(ctx context.Context, b BBox) ([]Stop, error) {
	cs := cells(b)
	missing, have := c.lookup(cs)
	if len(missing) > 0 {
		if err := c.acquire(ctx); err != nil {
			return nil, err
		}
		err := func() error {
			defer c.release()
			// another request may have fetched them while we waited
			if missing, _ = c.lookup(cs); len(missing) == 0 {
				return nil
			}
			lo, hi := span(missing)
			// finish and cache even if the app stops waiting: its retry
			// then finds the result
			stops, err := c.fetch(context.WithoutCancel(ctx), lo.box(hi))
			if err != nil {
				return err
			}
			c.store(cellRange(lo, hi), stops)
			return nil
		}()
		if err != nil {
			return nil, err
		}
		_, have = c.lookup(cs)
	}
	out := make([]Stop, 0, len(have))
	for _, s := range have {
		if s.Lat >= b.S && s.Lat <= b.N && s.Lon >= b.W && s.Lon <= b.E {
			out = append(out, s)
		}
	}
	return dedupe(out), nil
}

// acquire takes the upstream slot, keeping interval between queries; it
// gives up with errBusy after maxWait.
func (c *client) acquire(ctx context.Context) error {
	t := time.NewTimer(c.maxWait)
	defer t.Stop()
	select {
	case c.upstream <- struct{}{}:
	case <-t.C:
		return errBusy
	case <-ctx.Done():
		return ctx.Err()
	}
	c.mu.Lock()
	wait := time.Until(c.last.Add(c.interval))
	c.mu.Unlock()
	if wait > 0 {
		select {
		case <-time.After(wait):
		case <-ctx.Done():
			<-c.upstream
			return ctx.Err()
		}
	}
	return nil
}

func (c *client) release() {
	c.mu.Lock()
	c.last = time.Now()
	c.mu.Unlock()
	<-c.upstream
}

// span is the lowest and highest cell of cs. The cells from lo to hi are
// the ones a fetch stores, by index: going through the float box again
// would add the neighbours its edges touch, cached empty without a fetch.
func span(cs []cell) (lo, hi cell) {
	lo, hi = cs[0], cs[0]
	for _, k := range cs[1:] {
		lo.y, lo.x = min(lo.y, k.y), min(lo.x, k.x)
		hi.y, hi.x = max(hi.y, k.y), max(hi.x, k.x)
	}
	return lo, hi
}

// box is the area of the cells from c to hi.
func (c cell) box(hi cell) BBox {
	return BBox{
		S: float64(c.y) * cellDeg, W: float64(c.x) * cellDeg,
		N: float64(hi.y+1) * cellDeg, E: float64(hi.x+1) * cellDeg,
	}
}

type overpassResponse struct {
	Elements []struct {
		Type   string                      `json:"type"`
		ID     int64                       `json:"id"`
		Lat    float64                     `json:"lat"`
		Lon    float64                     `json:"lon"`
		Center *struct{ Lat, Lon float64 } `json:"center"`
		Tags   map[string]string           `json:"tags"`
	} `json:"elements"`
}

func query(b BBox) string {
	return fmt.Sprintf(`[out:json][timeout:25][bbox:%f,%f,%f,%f];
(
  nwr["public_transport"="station"];
  node["railway"~"^(station|halt|tram_stop)$"];
  node["highway"="bus_stop"];
  nwr["amenity"="ferry_terminal"];
);
out tags center qt;`, b.S, b.W, b.N, b.E)
}

func (c *client) fetch(ctx context.Context, b BBox) ([]Stop, error) {
	form := url.Values{"data": {query(b)}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.url, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("upstream status %d", resp.StatusCode)
	}
	var r overpassResponse
	if err := json.NewDecoder(resp.Body).Decode(&r); err != nil {
		return nil, err
	}
	out := make([]Stop, 0, len(r.Elements))
	for _, e := range r.Elements {
		kind := kindOf(e.Tags)
		if kind == "" {
			continue
		}
		lat, lon := e.Lat, e.Lon
		if e.Center != nil {
			lat, lon = e.Center.Lat, e.Center.Lon
		}
		if lat == 0 && lon == 0 {
			continue
		}
		out = append(out, Stop{
			ID: fmt.Sprintf("%c%d", e.Type[0], e.ID), Name: e.Tags["name"], Kind: kind, Lat: lat, Lon: lon,
		})
	}
	return out, nil
}

// kindOf classifies a stop by its OSM tags; "" for ones not to show.
func kindOf(t map[string]string) string {
	for _, k := range []string{"disused", "abandoned", "construction"} {
		if t[k] == "yes" {
			return ""
		}
	}
	if t["railway"] == "station" && t["usage"] == "tourism" {
		return ""
	}
	switch {
	case t["station"] == "subway" || t["subway"] == "yes":
		return "subway"
	case t["railway"] == "station" || t["railway"] == "halt" || t["train"] == "yes" ||
		t["station"] == "light_rail" || t["light_rail"] == "yes":
		return "train"
	case t["railway"] == "tram_stop" || t["tram"] == "yes":
		return "tram"
	case t["amenity"] == "ferry_terminal" || t["ferry"] == "yes":
		return "ferry"
	case t["highway"] == "bus_stop" || t["bus"] == "yes" || t["public_transport"] == "station":
		return "bus"
	}
	return ""
}

// dedupe merges stops of the same kind and name within dedupeMeters: OSM
// maps a stop once per platform or direction, and stations both as a node
// and as an area.
func dedupe(in []Stop) []Stop {
	out := make([]Stop, 0, len(in))
	groups := map[string][]int{} // kind+name -> indexes into out
	for _, s := range in {
		if s.Name == "" {
			out = append(out, s)
			continue
		}
		key := s.Kind + "\x00" + s.Name
		dup := false
		for _, i := range groups[key] {
			if meters(out[i], s) < dedupeMeters {
				dup = true
				break
			}
		}
		if !dup {
			groups[key] = append(groups[key], len(out))
			out = append(out, s)
		}
	}
	return out
}

func meters(a, b Stop) float64 {
	const r = 6371000
	dy := (b.Lat - a.Lat) * math.Pi / 180
	dx := (b.Lon - a.Lon) * math.Pi / 180 * math.Cos((a.Lat+b.Lat)/2*math.Pi/180)
	return r * math.Hypot(dx, dy)
}
