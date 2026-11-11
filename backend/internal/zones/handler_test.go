package zones

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/ratelimit"
	"stonerspots/backend/internal/testutil"
)

// fakeOverpass answers every query with body (or status code), counting hits
// and remembering the last request.
type fakeOverpass struct {
	srv   *httptest.Server
	hits  atomic.Int32
	code  atomic.Int32
	body  atomic.Pointer[string]
	mu    sync.Mutex
	query string
	hdr   http.Header
}

func newFakeOverpass(t *testing.T, body string) *fakeOverpass {
	t.Helper()
	f := &fakeOverpass{}
	f.body.Store(&body)
	f.code.Store(200)
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.hits.Add(1)
		_ = r.ParseForm()
		f.mu.Lock()
		f.query, f.hdr = r.PostForm.Get("data"), r.Header.Clone()
		f.mu.Unlock()
		w.WriteHeader(int(f.code.Load()))
		fmt.Fprint(w, *f.body.Load())
	}))
	t.Cleanup(f.srv.Close)
	return f
}

// memStore is a store in a map, standing in for the database.
type memStore struct {
	mu sync.Mutex
	m  map[string]tileData
}

func (s *memStore) load(_ context.Context, key string) (tileData, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.m[key]
	return d, ok, nil
}

func (s *memStore) save(_ context.Context, key string, d tileData) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.m[key] = d
	return nil
}

func (s *memStore) fetchedAt(_ context.Context, key string) (time.Time, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d, ok := s.m[key]
	return d.FetchedAt, ok, nil
}

const testBase = "https://spots.example.org"

// waitIdle waits until no block fetch is running.
func waitIdle(t *testing.T, s *Service) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		s.mu.Lock()
		n := len(s.inflight)
		s.mu.Unlock()
		if n == 0 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("fetch still running")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func testDeps(limit ratelimit.Rule, enabled bool) app.Deps {
	cfg := config.Config{PublicBaseURL: testBase, Zones: config.ZonesConfig{Enabled: enabled}}
	cfg.Limits.Zones = limit
	return app.Deps{Cfg: cfg}
}

func router(d app.Deps, s *Service) http.Handler {
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { mount(r, d, s) })
	return r
}

type apiResp struct {
	Zones       []Zone `json:"zones"`
	Attribution string `json:"attribution"`
	Stale       bool   `json:"stale"`
}

func get(t *testing.T, h http.Handler, s, w, n, e float64) (*httptest.ResponseRecorder, apiResp) {
	t.Helper()
	q := url.Values{}
	q.Set("south", fmt.Sprint(s))
	q.Set("west", fmt.Sprint(w))
	q.Set("north", fmt.Sprint(n))
	q.Set("east", fmt.Sprint(e))
	req := httptest.NewRequest("GET", "/api/v1/zones?"+q.Encode(), nil)
	req.RemoteAddr = "203.0.113.7:1234"
	req.Header.Set("X-Forwarded-For", "198.51.100.1")
	req.Header.Set("Authorization", "Bearer secret-user-token")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var body apiResp
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("decode: %v\n%s", err, rec.Body)
		}
	}
	return rec, body
}

func TestZonesEndpoint(t *testing.T) {
	f := newFakeOverpass(t, overpassFixture)
	st := &memStore{m: map[string]tileData{}}
	svc := NewService([]string{f.srv.URL}, testBase, st)
	h := router(testDeps(ratelimit.Rule{}, true), svc)

	rec, body := get(t, h, 48.12, 11.56, 48.14, 11.58)
	if rec.Code != 200 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	// the fixture's seven places, without the bar at 48.1/11.5: that is
	// outside the tile's block, so it is in none of its tiles
	if len(body.Zones) != 6 || body.Stale || body.Attribution != Attribution {
		t.Fatalf("body = %+v", body)
	}
	if !strings.Contains(rec.Body.String(), `"access_hours":"7-20"`) {
		t.Errorf("pedestrian zone without access_hours: %s", rec.Body)
	}
	if f.hits.Load() != 1 {
		t.Fatalf("upstream hits = %d", f.hits.Load())
	}

	// upstream request: the tile's query, an identifying User-Agent, nothing
	// from the client
	f.mu.Lock()
	query, hdr := f.query, f.hdr
	f.mu.Unlock()
	// the whole block of the tile: 4 × 4 tiles
	if !strings.Contains(query, "(48.080000,11.520000,48.160000,11.600000)") {
		t.Errorf("query for wrong block:\n%s", query)
	}
	ua := hdr.Get("User-Agent")
	if !strings.Contains(ua, "Stonerspots") || !strings.Contains(ua, testBase) || strings.Contains(ua, "@") {
		t.Errorf("User-Agent = %q", ua)
	}
	for _, k := range []string{"X-Forwarded-For", "X-Real-Ip", "Authorization", "Cookie", "Forwarded"} {
		if v := hdr.Get(k); v != "" {
			t.Errorf("upstream got %s: %q", k, v)
		}
	}

	// cached: a box inside the same tile does not go upstream again
	if rec, body := get(t, h, 48.125, 11.565, 48.13, 11.57); rec.Code != 200 || len(body.Zones) != 6 {
		t.Fatalf("cached: %d %+v", rec.Code, body)
	}
	if f.hits.Load() != 1 {
		t.Fatalf("cache missed: %d hits", f.hits.Load())
	}
	if _, ok := st.m["g2q2:2406:578"]; !ok {
		t.Fatalf("tile not stored: %v", st.m)
	}

	// the block's other tiles came with it: no fetch, zones in both tiles
	// are listed once
	rec, body = get(t, h, 48.12, 11.56, 48.14, 11.60)
	if rec.Code != 200 || len(body.Zones) != 6 || f.hits.Load() != 1 {
		t.Fatalf("two tiles: %d, %d zones, %d hits", rec.Code, len(body.Zones), f.hits.Load())
	}
	if _, ok := st.m["g2q2:2407:579"]; !ok {
		t.Fatalf("the block's other tiles were not stored")
	}
	// a tile of the next block: one more fetch
	if rec, _ := get(t, h, 48.16, 11.56, 48.18, 11.58); rec.Code != 200 || f.hits.Load() != 2 {
		t.Fatalf("next block: %d, %d hits", rec.Code, f.hits.Load())
	}
}

func TestZonesStaleOnUpstreamFailure(t *testing.T) {
	f := newFakeOverpass(t, overpassFixture)
	svc := NewService([]string{f.srv.URL}, testBase, &memStore{m: map[string]tileData{}})
	h := router(testDeps(ratelimit.Rule{}, true), svc)
	if rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58); rec.Code != 200 {
		t.Fatal(rec.Body)
	} else if got := rec.Header().Get("Cache-Control"); got != "public, max-age=3600" {
		t.Errorf("fresh answers: Cache-Control %q, want an hour", got)
	}

	// a week later Overpass is down: the old copy at once, marked stale,
	// while the refresh fails in the background
	start := time.Now()
	svc.now = func() time.Time { return start.Add(cacheTTL + time.Hour) }
	f.code.Store(http.StatusGatewayTimeout)
	rec, body := get(t, h, 48.12, 11.56, 48.14, 11.58)
	if rec.Code != 200 || !body.Stale || len(body.Zones) != 6 {
		t.Fatalf("stale: %d %+v", rec.Code, body)
	}
	if rec.Header().Get("Cache-Control") != "" {
		t.Errorf("stale answers must not be cached by clients")
	}
	waitIdle(t, svc)
	hits := f.hits.Load()
	// right after the failure it is not asked again (retryAfter)
	get(t, h, 48.12, 11.56, 48.14, 11.58)
	if f.hits.Load() != hits {
		t.Errorf("failed tile retried at once")
	}
	// a cut-short answer (remark) is a failure too, not new data
	svc.now = func() time.Time { return start.Add(cacheTTL + time.Hour + retryAfter + time.Second) }
	f.code.Store(200)
	cut := `{"elements":[],"remark":"runtime error: Query timed out"}`
	f.body.Store(&cut)
	if rec, body := get(t, h, 48.12, 11.56, 48.14, 11.58); rec.Code != 200 || !body.Stale || len(body.Zones) != 6 {
		t.Fatalf("remark: %d %+v", rec.Code, body)
	}
	waitIdle(t, svc)
	if svc.mem["g2q2:2406:578"].FetchedAt.After(start.Add(time.Minute)) {
		t.Errorf("a cut-short answer replaced the cached tile")
	}

	// no copy at all: 503
	if rec, _ := get(t, h, 50.0, 8.0, 50.01, 8.01); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("no data: %d", rec.Code)
	}
}

func TestZonesValidation(t *testing.T) {
	f := newFakeOverpass(t, overpassFixture)
	h := router(testDeps(ratelimit.Rule{}, true), NewService([]string{f.srv.URL}, testBase, nil))
	for _, b := range [][4]float64{
		{48.10, 11.50, 48.20, 11.52}, // too tall
		{48.10, 11.50, 48.12, 11.70}, // too wide
		{48.14, 11.56, 48.12, 11.58}, // inverted
	} {
		if rec, _ := get(t, h, b[0], b[1], b[2], b[3]); rec.Code != http.StatusBadRequest {
			t.Errorf("%v: %d", b, rec.Code)
		}
	}
	req := httptest.NewRequest("GET", "/api/v1/zones?south=48", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest || !strings.Contains(rec.Body.String(), "invalid_bbox") {
		t.Errorf("missing params: %d %s", rec.Code, rec.Body)
	}
	if f.hits.Load() != 0 {
		t.Errorf("invalid requests reached Overpass")
	}
}

func TestZonesDisabled(t *testing.T) {
	f := newFakeOverpass(t, overpassFixture)
	h := router(testDeps(ratelimit.Rule{}, false), NewService([]string{f.srv.URL}, testBase, nil))
	rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58)
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), "zones_disabled") || f.hits.Load() != 0 {
		t.Fatalf("disabled: %d %s", rec.Code, rec.Body)
	}
}

func TestZonesRateLimit(t *testing.T) {
	f := newFakeOverpass(t, overpassFixture)
	h := router(testDeps(ratelimit.Rule{N: 2, Per: time.Minute}, true), NewService([]string{f.srv.URL}, testBase, nil))
	for i := 0; i < 2; i++ {
		if rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58); rec.Code != 200 {
			t.Fatalf("request %d: %d", i, rec.Code)
		}
	}
	rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58)
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") == "" {
		t.Fatalf("third: %d", rec.Code)
	}
}

// At most maxUpstream queries reach Overpass at once; requests for the same
// tile share one query.
func TestZonesConcurrencyCap(t *testing.T) {
	var cur, peak, hits atomic.Int32
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		n := cur.Add(1)
		for {
			p := peak.Load()
			if n <= p || peak.CompareAndSwap(p, n) {
				break
			}
		}
		<-release
		cur.Add(-1)
		fmt.Fprint(w, `{"elements":[]}`)
	}))
	defer srv.Close()
	svc := NewService([]string{srv.URL}, testBase, nil)

	var wg sync.WaitGroup
	errs := make(chan error, 12)
	for i := 0; i < 6; i++ {
		for j := 0; j < 2; j++ { // two callers per tile
			wg.Go(func() {
				_, _, err := svc.Tile(context.Background(), Tile{Y: 2400 + BlockTiles*i, X: 578})
				errs <- err
			})
		}
	}
	deadline := time.Now().Add(5 * time.Second)
	for cur.Load() < maxUpstream && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	time.Sleep(100 * time.Millisecond) // give a third query the chance to sneak in
	if got := cur.Load(); got != maxUpstream {
		t.Fatalf("%d queries upstream at once, want %d", got, maxUpstream)
	}
	close(release)
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if peak.Load() != maxUpstream {
		t.Errorf("peak %d", peak.Load())
	}
	if hits.Load() != 6 {
		t.Errorf("%d upstream queries for 6 blocks", hits.Load())
	}
}

// A request that gives up does not stop the fetch: the tile is cached for
// the next one.
func TestZonesFetchOutlivesClient(t *testing.T) {
	release := make(chan struct{})
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		<-release
		fmt.Fprint(w, overpassFixture)
	}))
	defer srv.Close()
	svc := NewService([]string{srv.URL}, testBase, nil)
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if _, _, err := svc.Tile(ctx, Tile{2406, 578}); err == nil {
		t.Fatal("expected the caller to time out")
	}
	close(release)
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		svc.mu.Lock()
		_, ok := svc.mem["g2q2:2406:578"]
		svc.mu.Unlock()
		if ok {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	z, stale, err := svc.Tile(context.Background(), Tile{2406, 578})
	if err != nil || stale || len(z) != 6 || hits.Load() != 1 {
		t.Fatalf("after: %d zones, stale %v, err %v, hits %d", len(z), stale, err, hits.Load())
	}
}

// A tile still being fetched after pendingAfter answers 503 zones_pending
// with Retry-After; the fetch goes on and the next request is served from
// the cache.
func TestZonesPendingWhileFetching(t *testing.T) {
	old := pendingAfter
	pendingAfter = 50 * time.Millisecond
	t.Cleanup(func() { pendingAfter = old })
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-release
		fmt.Fprint(w, overpassFixture)
	}))
	defer srv.Close()
	svc := NewService([]string{srv.URL}, testBase, nil)
	h := router(testDeps(ratelimit.Rule{N: 100, Per: time.Minute}, true), svc)
	rec, _ := get(t, h, 48.121, 11.561, 48.125, 11.565)
	if rec.Code != http.StatusServiceUnavailable || !strings.Contains(rec.Body.String(), "zones_pending") {
		t.Fatalf("while fetching: %d %s", rec.Code, rec.Body)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("no Retry-After")
	}
	close(release)
	deadline := time.Now().Add(5 * time.Second)
	for {
		rec, body := get(t, h, 48.121, 11.561, 48.125, 11.565)
		if rec.Code == http.StatusOK {
			if len(body.Zones) == 0 {
				t.Fatal("no zones after the fetch")
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("still %d after the fetch", rec.Code)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// The database keeps tiles across restarts.
func TestZonesDBStore(t *testing.T) {
	d := testutil.NewDB(t)
	f := newFakeOverpass(t, overpassFixture)
	first := NewService([]string{f.srv.URL}, testBase, dbStore{db: d})
	z, _, err := first.Tile(context.Background(), Tile{2406, 578})
	if err != nil || len(z) != 6 {
		t.Fatalf("first: %v %d", err, len(z))
	}

	// "restart": a new service, same database, Overpass down
	f.code.Store(500)
	second := NewService([]string{f.srv.URL}, testBase, dbStore{db: d})
	z, stale, err := second.Tile(context.Background(), Tile{2406, 578})
	if err != nil || stale || len(z) != 6 || f.hits.Load() != 1 {
		t.Fatalf("after restart: %v stale=%v %d zones, %d hits", err, stale, len(z), f.hits.Load())
	}
	if z[1].Name != "Spielplatz Musterweg" || z[1].Geometry.Type != "Polygon" {
		t.Errorf("round trip changed the data: %+v", z[1])
	}

	// eight days old: answered at once, stale, and fetched again (which
	// fails upstream)
	if _, err := d.Exec(`UPDATE zone_tiles SET fetched_at = ?`, time.Now().Add(-8*24*time.Hour).UTC()); err != nil {
		t.Fatal(err)
	}
	third := NewService([]string{f.srv.URL}, testBase, dbStore{db: d})
	z, stale, err = third.Tile(context.Background(), Tile{2406, 578})
	if err != nil || !stale || len(z) != 6 {
		t.Fatalf("expired: %v stale=%v %d zones", err, stale, len(z))
	}
	waitIdle(t, third)
	if f.hits.Load() != 2 {
		t.Fatalf("expired tile not refreshed: %d hits", f.hits.Load())
	}
	if at, ok, err := (dbStore{db: d}).fetchedAt(context.Background(), "g2q2:2406:578"); err != nil || !ok ||
		time.Since(at) < 7*24*time.Hour {
		t.Fatalf("fetchedAt = %v %v %v", at, ok, err)
	}

	// Mount prunes long-unused tiles
	if _, err := d.Exec(`UPDATE zone_tiles SET fetched_at = ?`, time.Now().Add(-100*24*time.Hour).UTC()); err != nil {
		t.Fatal(err)
	}
	prune(app.Deps{DB: d})
	var n int
	if err := d.QueryRow(`SELECT COUNT(*) FROM zone_tiles`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("prune left %d rows (%v)", n, err)
	}
}

func TestZonesOnlyInGermany(t *testing.T) {
	// one playground on each side of the Konstanz/Kreuzlingen border, both
	// in tile 2382/458 (47.64-47.66, 9.16-9.18)
	const border = `{"elements":[
	 {"type":"node","id":1,"lat":47.6595,"lon":9.1755,"tags":{"leisure":"playground","name":"Konstanz"}},
	 {"type":"node","id":2,"lat":47.6500,"lon":9.1700,"tags":{"leisure":"playground","name":"Kreuzlingen"}}]}`
	if !InGermany(47.6595, 9.1755) || InGermany(47.65, 9.17) {
		t.Fatal("fixture points are not on the expected sides")
	}
	f := newFakeOverpass(t, border)
	h := router(testDeps(ratelimit.Rule{}, true), NewService([]string{f.srv.URL}, testBase, &memStore{m: map[string]tileData{}}))

	// Vienna: answered without asking Overpass
	rec, body := get(t, h, 48.20, 16.36, 48.22, 16.38)
	if rec.Code != 200 || len(body.Zones) != 0 || f.hits.Load() != 0 {
		t.Fatalf("Vienna: %d, %d zones, %d upstream hits", rec.Code, len(body.Zones), f.hits.Load())
	}

	// border tile: fetched, the Swiss place dropped
	rec, body = get(t, h, 47.64, 9.16, 47.66, 9.18)
	if rec.Code != 200 || f.hits.Load() != 1 {
		t.Fatalf("border: %d, %d upstream hits", rec.Code, f.hits.Load())
	}
	if len(body.Zones) != 1 || body.Zones[0].Name != "Konstanz" {
		t.Fatalf("border zones = %+v", body.Zones)
	}
}

// A tile that finds every upstream slot taken is "pending", not failed: the
// app keeps retrying it, and it is fetched as soon as a slot frees up.
func TestZonesBusyIsPending(t *testing.T) {
	var busy atomic.Bool
	busy.Store(true)
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if busy.Load() {
			<-release
		}
		fmt.Fprint(w, `{"elements":[]}`)
	}))
	defer srv.Close()
	var once sync.Once
	free := func() { once.Do(func() { busy.Store(false); close(release) }) }
	defer free() // before srv.Close, also when the test fails
	svc := NewService([]string{srv.URL}, testBase, nil)
	svc.slotWait = 20 * time.Millisecond
	h := router(testDeps(ratelimit.Rule{}, true), svc)

	// fill every slot with other tiles
	for i := 0; i < maxUpstream; i++ {
		go func() { _, _, _ = svc.Tile(context.Background(), Tile{Y: 2300 + BlockTiles*i, X: 578}) }()
	}
	deadline := time.Now().Add(5 * time.Second)
	for len(svc.sem) < maxUpstream && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}

	rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58)
	if rec.Code != http.StatusServiceUnavailable || !strings.Contains(rec.Body.String(), "zones_pending") ||
		rec.Header().Get("Retry-After") == "" {
		t.Fatalf("all slots busy: %d %s", rec.Code, rec.Body)
	}

	free()
	deadline = time.Now().Add(5 * time.Second)
	for len(svc.sem) > 0 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if rec, _ := get(t, h, 48.12, 11.56, 48.14, 11.58); rec.Code != 200 {
		t.Fatalf("after a slot freed up: %d %s", rec.Code, rec.Body)
	}
}
