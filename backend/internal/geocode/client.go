// Package geocode proxies address searches to a Nominatim-compatible geocoder
// with caching and rate limiting to respect its usage policy.
package geocode

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	userAgent   = "stonerspots/0.1 (+https://github.com/devilAPI/stonerspots)"
	maxResults  = 5
	cacheTTL    = 24 * time.Hour
	cacheMax    = 1000
	upstreamGap = time.Second
	maxWait     = 2 * time.Second
)

var errBusy = errors.New("geocoder busy")

// Result is one geocoding hit as returned to the app.
type Result struct {
	Label string  `json:"label"`
	Lat   float64 `json:"lat"`
	Lon   float64 `json:"lon"`
}

// client talks to Nominatim, fronted by a cache and a global limiter.
type client struct {
	baseURL  string
	http     *http.Client
	interval time.Duration
	maxWait  time.Duration

	mu    sync.Mutex
	next  time.Time // earliest start of the next upstream request
	cache map[string]cacheEntry
	order []string // insertion order for eviction
}

type cacheEntry struct {
	results []Result
	expires time.Time
}

func newClient(baseURL string, interval, wait time.Duration) *client {
	return &client{
		baseURL:  strings.TrimRight(baseURL, "/"),
		http:     &http.Client{Timeout: 5 * time.Second},
		interval: interval,
		maxWait:  wait,
		cache:    map[string]cacheEntry{},
	}
}

func cacheKey(q string) string {
	return strings.ToLower(strings.Join(strings.Fields(q), " "))
}

func (c *client) cached(key string) ([]Result, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.cache[key]
	if !ok || time.Now().After(e.expires) {
		return nil, false
	}
	return e.results, true
}

func (c *client) store(key string, res []Result) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, ok := c.cache[key]; !ok {
		c.order = append(c.order, key)
		for len(c.order) > cacheMax {
			delete(c.cache, c.order[0])
			c.order = c.order[1:]
		}
	}
	c.cache[key] = cacheEntry{results: res, expires: time.Now().Add(cacheTTL)}
}

// reserve claims the next upstream slot, returning how long to wait for it,
// or errBusy if that would exceed maxWait.
func (c *client) reserve() (time.Duration, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	now := time.Now()
	slot := c.next
	if slot.Before(now) {
		slot = now
	}
	wait := slot.Sub(now)
	if wait > c.maxWait {
		return 0, errBusy
	}
	c.next = slot.Add(c.interval)
	return wait, nil
}

// Search returns up to five results for q (already trimmed and validated).
func (c *client) Search(ctx context.Context, q string) ([]Result, error) {
	key := cacheKey(q)
	if res, ok := c.cached(key); ok {
		return res, nil
	}
	wait, err := c.reserve()
	if err != nil {
		return nil, err
	}
	if wait > 0 {
		t := time.NewTimer(wait)
		select {
		case <-t.C:
		case <-ctx.Done():
			t.Stop()
			return nil, ctx.Err()
		}
	}
	res, err := c.fetch(ctx, q)
	if err != nil {
		return nil, err
	}
	c.store(key, res)
	return res, nil
}

type nominatimItem struct {
	DisplayName string `json:"display_name"`
	Lat         string `json:"lat"`
	Lon         string `json:"lon"`
}

func (c *client) fetch(ctx context.Context, q string) ([]Result, error) {
	v := url.Values{}
	v.Set("format", "jsonv2")
	v.Set("q", q)
	v.Set("limit", strconv.Itoa(maxResults))
	v.Set("countrycodes", "de,at,ch,li")
	v.Set("accept-language", "de")
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/search?"+v.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", userAgent)
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("upstream status %d", resp.StatusCode)
	}
	var items []nominatimItem
	if err := json.NewDecoder(resp.Body).Decode(&items); err != nil {
		return nil, err
	}
	out := make([]Result, 0, maxResults)
	for _, it := range items {
		lat, err1 := strconv.ParseFloat(it.Lat, 64)
		lon, err2 := strconv.ParseFloat(it.Lon, 64)
		if err1 != nil || err2 != nil || it.DisplayName == "" {
			continue
		}
		out = append(out, Result{Label: it.DisplayName, Lat: lat, Lon: lon})
		if len(out) == maxResults {
			break
		}
	}
	return out, nil
}
