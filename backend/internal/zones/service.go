package zones

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

const (
	// queryTimeout is the [timeout:] of the Overpass query; the HTTP request
	// may take a little longer (queueing at Overpass, transfer).
	queryTimeout = 25 * time.Second
	httpTimeout  = queryTimeout + 10*time.Second
	// maxUpstream Overpass queries run at once (Overpass allows a couple of
	// slots per client IP; more would only queue there).
	maxUpstream = 2
	// slotWait is how long a tile waits for a free upstream slot.
	slotWait = 30 * time.Second
	// cacheTTL: OSM changes slowly, and Overpass is a shared, free service.
	cacheTTL = 7 * 24 * time.Hour
	// retryAfter: a tile whose fetch failed is not asked for again before
	// this (callers get the stale copy or an error meanwhile).
	retryAfter = time.Minute
	// memTiles bounds the in-memory cache; the database keeps the rest.
	memTiles = 500
)

var (
	errUnavailable = errors.New("zones: upstream unavailable")
	errBusy        = errors.New("zones: upstream busy")
)

// tileData is one cached tile.
type tileData struct {
	Zones     []Zone    `json:"zones"`
	FetchedAt time.Time `json:"-"`
}

// store keeps tiles across restarts (MariaDB in production; nil = memory only).
type store interface {
	load(ctx context.Context, key string) (tileData, bool, error)
	save(ctx context.Context, key string, d tileData) error
}

// call is one upstream fetch that several requests may wait for.
type call struct {
	done chan struct{}
	data tileData
	err  error
}

// Service answers zone requests from the tile cache and Overpass.
type Service struct {
	url       string
	userAgent string
	http      *http.Client
	store     store
	now       func() time.Time
	sem       chan struct{}
	slotWait  time.Duration

	mu       sync.Mutex
	mem      map[string]tileData
	order    []string             // insertion order of mem, for eviction
	inflight map[string]*call     // tile key -> running fetch
	failed   map[string]time.Time // tile key -> no new fetch before
}

// NewService builds the service; publicBaseURL names the operator in the
// User-Agent (Overpass asks clients to identify themselves).
func NewService(overpassURL, publicBaseURL string, st store) *Service {
	return &Service{
		url:       overpassURL,
		userAgent: userAgent(publicBaseURL),
		http:      &http.Client{Timeout: httpTimeout},
		store:     st,
		now:       time.Now,
		sem:       make(chan struct{}, maxUpstream),
		slotWait:  slotWait,
		mem:       map[string]tileData{},
		inflight:  map[string]*call{},
		failed:    map[string]time.Time{},
	}
}

func userAgent(publicBaseURL string) string {
	return fmt.Sprintf("Stonerspots zone layer (+https://github.com/devilAPI/stonerspots; operator %s)",
		strings.TrimRight(publicBaseURL, "/"))
}

func (s *Service) fresh(d tileData) bool { return s.now().Sub(d.FetchedAt) < cacheTTL }

func (s *Service) remember(key string, d tileData) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.mem[key]; !ok {
		s.order = append(s.order, key)
		for len(s.order) > memTiles {
			delete(s.mem, s.order[0])
			s.order = s.order[1:]
		}
	}
	s.mem[key] = d
}

func (s *Service) cached(ctx context.Context, key string) (tileData, bool) {
	s.mu.Lock()
	d, ok := s.mem[key]
	s.mu.Unlock()
	if ok || s.store == nil {
		return d, ok
	}
	d, ok, err := s.store.load(ctx, key)
	if err != nil {
		return tileData{}, false
	}
	if ok {
		s.remember(key, d)
	}
	return d, ok
}

// Tile returns the zones of t: from the cache while fresh, else from
// Overpass. When Overpass fails, an expired copy is served with stale set.
func (s *Service) Tile(ctx context.Context, t Tile) (zones []Zone, stale bool, err error) {
	key := t.Key()
	old, have := s.cached(ctx, key)
	if have && s.fresh(old) {
		return old.Zones, false, nil
	}
	d, err := s.fetchShared(ctx, t)
	if err == nil {
		return d.Zones, false, nil
	}
	if have {
		return old.Zones, true, nil
	}
	return nil, false, err
}

// fetchShared starts the upstream fetch of t, or joins one that is running.
// The fetch is not tied to the request: when the client gives up, the tile
// is still cached for the next one.
func (s *Service) fetchShared(ctx context.Context, t Tile) (tileData, error) {
	key := t.Key()
	s.mu.Lock()
	if until, ok := s.failed[key]; ok && s.now().Before(until) {
		s.mu.Unlock()
		return tileData{}, errUnavailable
	}
	c, running := s.inflight[key]
	if !running {
		c = &call{done: make(chan struct{})}
		s.inflight[key] = c
		go s.run(key, t, c)
	}
	s.mu.Unlock()
	select {
	case <-c.done:
		return c.data, c.err
	case <-ctx.Done():
		return tileData{}, ctx.Err()
	}
}

func (s *Service) run(key string, t Tile, c *call) {
	ctx, cancel := context.WithTimeout(context.Background(), s.slotWait+httpTimeout)
	defer cancel()
	c.data, c.err = s.fetch(ctx, t)
	if c.err == nil {
		s.remember(key, c.data)
		if s.store != nil {
			if err := s.store.save(ctx, key, c.data); err != nil {
				log.Printf("zones: save tile %s: %v", key, err) // still in memory
			}
		}
	} else {
		log.Printf("zones: tile %s: %v", key, c.err)
	}
	s.mu.Lock()
	delete(s.inflight, key)
	now := s.now()
	if c.err != nil {
		s.failed[key] = now.Add(retryAfter)
	} else {
		delete(s.failed, key)
	}
	for k, until := range s.failed { // keep the map small
		if now.After(until) {
			delete(s.failed, k)
		}
	}
	s.mu.Unlock()
	close(c.done)
}

// fetch asks Overpass for one tile, at most maxUpstream at a time.
func (s *Service) fetch(ctx context.Context, t Tile) (tileData, error) {
	wait := time.NewTimer(s.slotWait)
	defer wait.Stop()
	select {
	case s.sem <- struct{}{}:
	case <-wait.C:
		return tileData{}, errBusy
	case <-ctx.Done():
		return tileData{}, ctx.Err()
	}
	defer func() { <-s.sem }()

	// Only the query goes upstream: no client address, no user data.
	form := url.Values{"data": {buildQuery(t)}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.url, strings.NewReader(form.Encode()))
	if err != nil {
		return tileData{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", s.userAgent)
	req.Header.Set("Accept", "application/json")
	resp, err := s.http.Do(req)
	if err != nil {
		return tileData{}, fmt.Errorf("%w: %v", errUnavailable, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return tileData{}, fmt.Errorf("%w: status %d", errUnavailable, resp.StatusCode)
	}
	zones, err := parseOverpass(resp.Body)
	if err != nil {
		return tileData{}, fmt.Errorf("%w: %v", errUnavailable, err)
	}
	return tileData{Zones: zones, FetchedAt: s.now()}, nil
}
