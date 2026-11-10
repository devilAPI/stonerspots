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
	// queryTimeout is the [timeout:] of the Overpass query, for one block
	// (BlockTiles × BlockTiles tiles).
	queryTimeout = 60 * time.Second
	// httpTimeout bounds one request to one Overpass server, queueing there
	// included; then the next server is tried.
	httpTimeout = queryTimeout + 30*time.Second
	// maxUpstream Overpass queries run at once (Overpass allows a couple of
	// slots per client IP; more would only queue there).
	maxUpstream = 2
	// slotWait is how long a block waits for a free upstream slot.
	slotWait = 30 * time.Second
	// cacheTTL: after this a tile is fetched again. Until then, and while
	// that fails, the cached copy is served (OSM changes slowly, and
	// Overpass is a shared, free service).
	cacheTTL = 7 * 24 * time.Hour
	// retryAfter: a block whose fetch failed on every server is not asked
	// for again before this.
	retryAfter = time.Minute
	// serverCooldown: a server that failed is skipped this long, unless
	// every server is cooling down.
	serverCooldown = 2 * time.Minute
	// memTiles bounds the in-memory cache; the database keeps the rest.
	memTiles = 2000
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
	// fetchedAt tells when the tile was stored, without reading its zones.
	fetchedAt(ctx context.Context, key string) (time.Time, bool, error)
}

// call is one upstream fetch of a block that several requests may wait for.
type call struct {
	done  chan struct{}
	tiles map[string]tileData // tile key -> its part of the block
	err   error
}

// Service answers zone requests from the tile cache and Overpass. Tiles are
// fetched by block: one query for BlockTiles × BlockTiles tiles, so a view
// (a handful of tiles) costs one or a few queries instead of one per tile.
type Service struct {
	urls      []string
	userAgent string
	http      *http.Client
	store     store
	now       func() time.Time
	sem       chan struct{}
	slotWait  time.Duration

	mu       sync.Mutex
	mem      map[string]tileData
	order    []string             // insertion order of mem, for eviction
	inflight map[string]*call     // block key -> running fetch
	failed   map[string]time.Time // block key -> no new fetch before
	// preferred is the server that answered last; cooling are servers that
	// failed, until when they are skipped
	preferred int
	cooling   map[int]time.Time
}

// NewService builds the service. overpassURLs are tried in turn when one
// fails; publicBaseURL names the operator in the User-Agent (Overpass asks
// clients to identify themselves).
func NewService(overpassURLs []string, publicBaseURL string, st store) *Service {
	return &Service{
		urls:      overpassURLs,
		userAgent: userAgent(publicBaseURL),
		http:      &http.Client{Timeout: httpTimeout},
		store:     st,
		now:       time.Now,
		sem:       make(chan struct{}, maxUpstream),
		slotWait:  slotWait,
		mem:       map[string]tileData{},
		inflight:  map[string]*call{},
		failed:    map[string]time.Time{},
		cooling:   map[int]time.Time{},
	}
}

func userAgent(publicBaseURL string) string {
	return fmt.Sprintf("Stonerspots zone layer (+https://github.com/devilAPI/stonerspots; operator %s)",
		strings.TrimRight(publicBaseURL, "/"))
}

func (s *Service) fresh(at time.Time) bool { return s.now().Sub(at) < cacheTTL }

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

// Tile returns the zones of t. A cached copy is answered at once: when it
// is older than cacheTTL its block is fetched again in the background, and
// the copy is marked stale. Without a copy the caller waits for the block
// (until ctx ends).
func (s *Service) Tile(ctx context.Context, t Tile) (zones []Zone, stale bool, err error) {
	key := t.Key()
	old, have := s.cached(ctx, key)
	if have {
		if s.fresh(old.FetchedAt) {
			return old.Zones, false, nil
		}
		s.start(blockOf(t)) // refresh; this answer does not wait for it
		return old.Zones, true, nil
	}
	c, err := s.start(blockOf(t))
	if err != nil {
		return nil, false, err
	}
	select {
	case <-c.done:
	case <-ctx.Done():
		return nil, false, ctx.Err()
	}
	if c.err != nil {
		return nil, false, c.err
	}
	return c.tiles[key].Zones, false, nil
}

// start begins the upstream fetch of b, or returns the one that is running.
// The fetch is not tied to any request: when the client gives up, the
// tiles are still cached for the next one.
func (s *Service) start(b block) (*call, error) {
	key := b.Key()
	s.mu.Lock()
	defer s.mu.Unlock()
	if c, ok := s.inflight[key]; ok {
		return c, nil
	}
	if until, ok := s.failed[key]; ok && s.now().Before(until) {
		return nil, errUnavailable
	}
	c := &call{done: make(chan struct{})}
	s.inflight[key] = c
	go s.run(key, b, c)
	return c, nil
}

func (s *Service) run(key string, b block, c *call) {
	ctx, cancel := context.WithTimeout(context.Background(),
		s.slotWait+time.Duration(len(s.urls))*httpTimeout)
	defer cancel()
	zones, at, err := s.fetch(ctx, b)
	c.err = err
	if err == nil {
		c.tiles = map[string]tileData{}
		for t, z := range splitBlock(b, zones) {
			d := tileData{Zones: z, FetchedAt: at}
			c.tiles[t.Key()] = d
			s.remember(t.Key(), d)
			if s.store != nil {
				if err := s.store.save(ctx, t.Key(), d); err != nil {
					log.Printf("zones: save tile %s: %v", t.Key(), err) // still in memory
				}
			}
		}
	} else {
		log.Printf("zones: block %s: %v", key, err)
	}
	s.mu.Lock()
	delete(s.inflight, key)
	now := s.now()
	// a full queue says nothing about the block: the next request may try
	// again right away
	if err != nil && !errors.Is(err, errBusy) {
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

// fetch asks Overpass for one block, at most maxUpstream at a time: the
// server that answered last first, then the others.
func (s *Service) fetch(ctx context.Context, b block) ([]Zone, time.Time, error) {
	wait := time.NewTimer(s.slotWait)
	defer wait.Stop()
	select {
	case s.sem <- struct{}{}:
	case <-wait.C:
		return nil, time.Time{}, errBusy
	case <-ctx.Done():
		return nil, time.Time{}, ctx.Err()
	}
	defer func() { <-s.sem }()

	query := buildQuery(b.Bounds())
	var errs []error
	for _, i := range s.serverOrder() {
		zones, err := s.ask(ctx, s.urls[i], query)
		s.mu.Lock()
		if err == nil {
			s.preferred = i
			delete(s.cooling, i)
		} else {
			s.cooling[i] = s.now().Add(serverCooldown)
		}
		s.mu.Unlock()
		if err == nil {
			return zones, s.now(), nil
		}
		errs = append(errs, err)
		if ctx.Err() != nil {
			break
		}
	}
	return nil, time.Time{}, errors.Join(errs...)
}

// serverOrder is the order to try the servers in: the preferred one, then
// the rest; servers cooling down after a failure last.
func (s *Service) serverOrder() []int {
	s.mu.Lock()
	defer s.mu.Unlock()
	now := s.now()
	var ready, cooling []int
	for k := range s.urls {
		i := (s.preferred + k) % len(s.urls)
		if until, ok := s.cooling[i]; ok && now.Before(until) {
			cooling = append(cooling, i)
		} else {
			ready = append(ready, i)
		}
	}
	return append(ready, cooling...)
}

// ask sends query to one Overpass server. Only the query goes upstream: no
// client address, no user data.
func (s *Service) ask(ctx context.Context, server, query string) ([]Zone, error) {
	form := url.Values{"data": {query}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, server, strings.NewReader(form.Encode()))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", s.userAgent)
	req.Header.Set("Accept", "application/json")
	resp, err := s.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: %s: %v", errUnavailable, host(server), err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: %s: status %d", errUnavailable, host(server), resp.StatusCode)
	}
	zones, err := parseOverpass(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("%w: %s: %v", errUnavailable, host(server), err)
	}
	return zones, nil
}

func host(server string) string {
	if u, err := url.Parse(server); err == nil && u.Host != "" {
		return u.Host
	}
	return server
}
