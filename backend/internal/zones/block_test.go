package zones

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

func point(id string, lat, lon float64) Zone {
	c, _ := json.Marshal([2]float64{lat, lon})
	return Zone{ID: id, Kind: KindPlayground, Geometry: Geometry{Type: "Point", Coordinates: c}}
}

func line(id string, pts ...[2]float64) Zone {
	c, _ := json.Marshal(pts)
	return Zone{ID: id, Kind: KindPedestrian, Geometry: Geometry{Type: "LineString", Coordinates: c}}
}

func TestBlockGrid(t *testing.T) {
	b := blockOf(Tile{Y: 2406, X: 578})
	if b != (block{Y: 601, X: 144}) {
		t.Fatalf("block = %+v", b)
	}
	if got := blockOf(Tile{Y: -1, X: -5}); got != (block{Y: -1, X: -2}) {
		t.Fatalf("negative: %+v", got)
	}
	tiles := b.Tiles()
	if len(tiles) != 16 || tiles[0] != (Tile{2404, 576}) || tiles[15] != (Tile{2407, 579}) {
		t.Fatalf("tiles = %v", tiles)
	}
	s, w, n, e := b.Bounds()
	if fmt.Sprintf("%.2f %.2f %.2f %.2f", s, w, n, e) != "48.08 11.52 48.16 11.60" {
		t.Fatalf("bounds %v %v %v %v", s, w, n, e)
	}
}

func TestSplitBlock(t *testing.T) {
	b := block{Y: 601, X: 144} // 48.08-48.16, 11.52-11.60
	got := splitBlock(b, []Zone{
		point("in", 48.125, 11.565), // tile 2406/578
		line("across", [2]float64{48.13, 11.575}, [2]float64{48.13, 11.585}), // 578 and 579
		point("outside", 48.10, 11.50),                                       // west of the block
	})
	if len(got) != 16 {
		t.Fatalf("%d tiles, want all 16", len(got))
	}
	ids := func(tl Tile) (out []string) {
		for _, z := range got[tl] {
			out = append(out, z.ID)
		}
		return out
	}
	if fmt.Sprint(ids(Tile{2406, 578})) != "[in across]" {
		t.Errorf("2406/578: %v", ids(Tile{2406, 578}))
	}
	if fmt.Sprint(ids(Tile{2406, 579})) != "[across]" {
		t.Errorf("2406/579: %v", ids(Tile{2406, 579}))
	}
	if got[Tile{2404, 576}] == nil || len(got[Tile{2404, 576}]) != 0 {
		t.Errorf("an empty tile must be there, empty: %v", got[Tile{2404, 576}])
	}
	for tl, zs := range got {
		for _, z := range zs {
			if z.ID == "outside" {
				t.Errorf("place outside the block in tile %v", tl)
			}
		}
	}
}

// One server failing does not fail the tile: the next is asked, and is
// asked first from then on.
func TestZonesServerFailover(t *testing.T) {
	var badHits, goodHits atomic.Int32
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		badHits.Add(1)
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer bad.Close()
	good := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		goodHits.Add(1)
		fmt.Fprint(w, overpassFixture)
	}))
	defer good.Close()
	svc := NewService([]string{bad.URL, good.URL}, testBase, nil)
	z, stale, err := svc.Tile(context.Background(), Tile{2406, 578})
	if err != nil || stale || len(z) != 6 {
		t.Fatalf("failover: %v stale=%v %d zones", err, stale, len(z))
	}
	if badHits.Load() != 1 || goodHits.Load() != 1 {
		t.Fatalf("hits bad %d good %d", badHits.Load(), goodHits.Load())
	}
	// another block: the server that answered goes first
	if _, _, err := svc.Tile(context.Background(), Tile{2410, 578}); err != nil {
		t.Fatal(err)
	}
	if badHits.Load() != 1 || goodHits.Load() != 2 {
		t.Fatalf("after: hits bad %d good %d", badHits.Load(), goodHits.Load())
	}
	// every server failing: an error naming each
	good.Close()
	_, _, err = svc.Tile(context.Background(), Tile{2420, 578})
	if err == nil {
		t.Fatal("expected an error with every server down")
	}
}

// An expired tile is answered at once from the cache; the refresh runs in
// the background and replaces it when it arrives.
func TestZonesStaleAnsweredAtOnce(t *testing.T) {
	release := make(chan struct{})
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) > 1 {
			<-release
		}
		fmt.Fprint(w, overpassFixture)
	}))
	defer srv.Close()
	defer close(release)
	svc := NewService([]string{srv.URL}, testBase, nil)
	if _, _, err := svc.Tile(context.Background(), Tile{2406, 578}); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	svc.now = func() time.Time { return start.Add(cacheTTL + time.Hour) }
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	began := time.Now()
	z, stale, err := svc.Tile(ctx, Tile{2406, 578})
	if err != nil || !stale || len(z) != 6 || time.Since(began) > 200*time.Millisecond {
		t.Fatalf("expired: %v stale=%v %d zones after %v", err, stale, len(z), time.Since(began))
	}
	deadline := time.Now().Add(5 * time.Second)
	for hits.Load() < 2 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if hits.Load() != 2 {
		t.Fatalf("no refresh started: %d hits", hits.Load())
	}
}

func TestGermanBlocks(t *testing.T) {
	all := germanBlocks()
	// Germany is about 357 000 km², a block about 50 km²
	if len(all) < 5000 || len(all) > 12000 {
		t.Fatalf("%d blocks", len(all))
	}
	seen := map[block]bool{}
	for _, b := range all {
		seen[b] = true
	}
	if !seen[blockOf(tileAt(48.137, 11.575))] || !seen[blockOf(tileAt(53.55, 9.99))] {
		t.Error("Munich or Hamburg missing")
	}
	if seen[blockOf(tileAt(48.20, 16.37))] {
		t.Error("Vienna is not in Germany")
	}
	// spots first: Hamburg's block before the rest
	order := prefetchOrder([][2]float64{{53.55, 9.99}, {53.551, 9.991}, {48.137, 11.575}})
	if order[0] != blockOf(tileAt(53.55, 9.99)) || order[1] != blockOf(tileAt(48.137, 11.575)) {
		t.Errorf("order starts %v %v", order[0], order[1])
	}
	if len(order) != len(all) {
		t.Errorf("order has %d blocks, want %d", len(order), len(all))
	}
}

// The prefetch fetches the blocks that are missing or due, one at a time,
// and skips fresh ones.
func TestPrefetch(t *testing.T) {
	oldPause, oldIdle := prefetchPause, prefetchIdle
	prefetchPause, prefetchIdle = time.Millisecond, time.Hour
	t.Cleanup(func() { prefetchPause, prefetchIdle = oldPause, oldIdle })

	var hits, cur, peak atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		n := cur.Add(1)
		if n > peak.Load() {
			peak.Store(n)
		}
		time.Sleep(5 * time.Millisecond)
		cur.Add(-1)
		fmt.Fprint(w, `{"elements":[]}`)
	}))
	defer srv.Close()
	st := &memStore{m: map[string]tileData{}}
	svc := NewService([]string{srv.URL}, testBase, st)
	munich, hamburg := blockOf(tileAt(48.137, 11.575)), blockOf(tileAt(53.55, 9.99))
	berlin := blockOf(tileAt(52.52, 13.40))
	// Hamburg is fresh: every tile stored just now
	for _, tl := range hamburg.Tiles() {
		st.m[tl.Key()] = tileData{Zones: []Zone{}, FetchedAt: time.Now()}
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		svc.Prefetch(ctx, func(context.Context) []block { return []block{munich, hamburg, berlin} })
		close(done)
	}()
	deadline := time.Now().Add(5 * time.Second)
	for hits.Load() < 2 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	time.Sleep(50 * time.Millisecond)
	cancel()
	<-done
	if hits.Load() != 2 || peak.Load() != 1 {
		t.Fatalf("%d queries (want Munich and Berlin), %d at once", hits.Load(), peak.Load())
	}
	for _, b := range []block{munich, berlin} {
		if _, ok := st.m[b.Tiles()[5].Key()]; !ok {
			t.Errorf("block %v not stored", b)
		}
	}
}
