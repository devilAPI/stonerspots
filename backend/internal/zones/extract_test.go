package zones

import (
	"context"
	"crypto/md5"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/paulmach/osm"
)

func TestCandidateMatchesKindOf(t *testing.T) {
	cases := []struct {
		tags osm.Tags
		node bool
		want string
	}{
		{osm.Tags{{Key: "amenity", Value: "school"}, {Key: "name", Value: "GS"}}, false, KindSchool},
		{osm.Tags{{Key: "building", Value: "kindergarten"}}, false, KindKindergarten},
		{osm.Tags{{Key: "leisure", Value: "pitch"}}, false, KindSports},
		{osm.Tags{{Key: "leisure", Value: "pitch"}, {Key: "access", Value: "private"}}, false, ""},
		{osm.Tags{{Key: "leisure", Value: "playground"}, {Key: "access", Value: "private"}}, false, KindPlayground},
		{osm.Tags{{Key: "amenity", Value: "social_facility"}, {Key: "social_facility:for", Value: "juvenile"}}, false, KindYouth},
		{osm.Tags{{Key: "amenity", Value: "social_facility"}, {Key: "social_facility:for", Value: "senior"}}, false, ""},
		{osm.Tags{{Key: "amenity", Value: "cafe"}, {Key: "smoking:cannabis", Value: "no"}}, false, KindExplicit},
		{osm.Tags{{Key: "highway", Value: "pedestrian"}}, false, KindPedestrian},
		// like the Overpass query: pedestrian zones are ways and relations
		{osm.Tags{{Key: "highway", Value: "pedestrian"}}, true, ""},
		{osm.Tags{{Key: "building", Value: "yes"}, {Key: "highway", Value: "residential"}}, false, ""},
	}
	for _, c := range cases {
		got := ""
		if m := zoneTags(c.tags, c.node); m != nil {
			got = kindOf(m)
		}
		if got != c.want {
			t.Errorf("%v (node %v): %q, want %q", c.tags, c.node, got, c.want)
		}
	}
}

func TestNodeCoords(t *testing.T) {
	c := newNodeCoords([]int64{30, 10, 20, 10})
	c.set(20, 48.1234567, 11.7654321)
	c.set(99, 1, 1) // not asked for
	if p := c.point(20); p == nil || p.Lat != 48.1234567 || p.Lon != 11.7654321 {
		t.Fatalf("point(20) = %+v", p)
	}
	if c.point(10) != nil || c.point(99) != nil {
		t.Fatal("nodes not seen must have no point")
	}
	if got := len(c.ids); got != 3 {
		t.Fatalf("ids not deduplicated: %d", got)
	}
}

func TestTilesFromZonesCoverGermanyAndSplit(t *testing.T) {
	// a school in Munich, and a pedestrian street across a block edge
	// (0.08° grid: 11.60 is one)
	school := Zone{ID: "way/1", Kind: KindSchool}
	school.Geometry, _ = encode("Point", pt{48.13, 11.57})
	street := Zone{ID: "way/2", Kind: KindPedestrian}
	street.Geometry, _ = encode("LineString", []pt{{48.15, 11.59}, {48.15, 11.61}})

	got := map[Tile][]Zone{}
	err := tilesFromZones(context.Background(), []Zone{school, street}, func(t Tile, z []Zone) error {
		got[t] = z
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(got) < 50000 {
		t.Fatalf("only %d tiles: every German tile must be written, empty ones too", len(got))
	}
	if _, ok := got[tileAt(51.5, -0.12)]; ok {
		t.Fatal("London is not in Germany")
	}
	if z := got[tileAt(48.13, 11.57)]; len(z) != 1 || z[0].ID != "way/1" {
		t.Fatalf("Munich tile: %+v", z)
	}
	for _, lon := range []float64{11.59, 11.61} {
		z := got[tileAt(48.15, lon)]
		if len(z) != 1 || z[0].ID != "way/2" {
			t.Fatalf("street missing from the tile at %v: %+v", lon, z)
		}
	}
	if z := got[tileAt(52.52, 13.40)]; z == nil || len(z) != 0 {
		t.Fatalf("Berlin must be an empty tile, got %+v", z)
	}
}

// serveExtract serves the file at path as an extract, with md5sum as its
// .md5 file.
func serveExtract(t *testing.T, path string, md5sum string) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/germany.osm.pbf":
			w.Header().Set("Last-Modified", "Tue, 10 Nov 2026 20:00:00 GMT")
			http.ServeFile(w, r, path)
		case "/germany.osm.pbf.md5":
			w.Write([]byte(md5sum + "  germany.osm.pbf\n"))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return srv.URL + "/germany.osm.pbf"
}

func TestDownloadChecksMD5(t *testing.T) {
	body := []byte("not really a pbf")
	sum := md5.Sum(body)
	src := filepath.Join(t.TempDir(), "src.pbf")
	if err := os.WriteFile(src, body, 0o644); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	s := NewService(nil, testBase, nil)
	path := filepath.Join(dir, extractFile)

	url := serveExtract(t, src, hex.EncodeToString(sum[:]))
	if _, err := s.download(context.Background(), url, path); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(path); string(b) != string(body) {
		t.Fatalf("downloaded %q", b)
	}

	bad := serveExtract(t, src, "0123456789abcdef0123456789abcdef")
	os.Remove(path)
	if _, err := s.download(context.Background(), bad, path); err == nil {
		t.Fatal("a wrong checksum must fail")
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("a download that failed the check must not be kept")
	}
}

func TestDownloadChecksTheMirrorsMD5(t *testing.T) {
	body := []byte("not really a pbf")
	src := filepath.Join(t.TempDir(), "src.pbf")
	if err := os.WriteFile(src, body, 0o644); err != nil {
		t.Fatal(err)
	}
	// like Geofabrik: the main host redirects, only the mirror has the .md5
	mirror := serveExtract(t, src, "0123456789abcdef0123456789abcdef")
	main := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".md5") {
			http.NotFound(w, r)
			return
		}
		http.Redirect(w, r, mirror, http.StatusTemporaryRedirect)
	}))
	defer main.Close()
	s := NewService(nil, testBase, nil)
	path := filepath.Join(t.TempDir(), extractFile)
	if _, err := s.download(context.Background(), main.URL+"/germany.osm.pbf", path); err == nil {
		t.Fatal("the mirror's checksum must be checked")
	}
}

func TestRunExtractWaitsForTheNextRound(t *testing.T) {
	dir := t.TempDir()
	if err := writeState(dir, extractState{ImportedAt: time.Now()}); err != nil {
		t.Fatal(err)
	}
	hit := make(chan struct{}, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hit <- struct{}{}
	}))
	defer srv.Close()
	s := NewService(nil, testBase, &memStore{m: map[string]tileData{}})
	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	s.RunExtract(ctx, srv.URL, dir) // returns when ctx ends
	select {
	case <-hit:
		t.Fatal("imported again although the last import is fresh")
	default:
	}
}

// peakRSS is the process's peak resident memory (Linux), or "".
func peakRSS() string {
	b, _ := os.ReadFile("/proc/self/status")
	for _, l := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(l, "VmHWM:") {
			return "peak RSS " + strings.Join(strings.Fields(l)[1:], " ")
		}
	}
	return ""
}

// tallyStore counts what is saved and keeps only the tile named probe.
type tallyStore struct {
	mu    sync.Mutex
	probe string
	kept  tileData
	tiles int
	kinds map[string]int
	seen  map[string]bool
}

func (s *tallyStore) load(context.Context, string) (tileData, bool, error) {
	return tileData{}, false, nil
}

func (s *tallyStore) fetchedAt(context.Context, string) (time.Time, bool, error) {
	return time.Time{}, false, nil
}

func (s *tallyStore) save(_ context.Context, key string, d tileData) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tiles++
	for _, z := range d.Zones {
		if !s.seen[z.ID] {
			s.seen[z.ID] = true
			s.kinds[z.Kind+"/"+z.Geometry.Type]++
		}
	}
	if key == s.probe {
		s.kept = d
	}
	return nil
}

// With ZONES_TEST_PBF set to an extract (e.g. Geofabrik's bremen-latest
// .osm.pbf), the whole import runs on it: download, read, tiles. Its md5 is
// taken from the .md5 file next to it, or computed. ZONES_TEST_TILE (a
// tile key) lists that tile's zones.
func TestImportExtractFile(t *testing.T) {
	file := os.Getenv("ZONES_TEST_PBF")
	if file == "" {
		t.Skip("ZONES_TEST_PBF not set")
	}
	sum := ""
	if b, err := os.ReadFile(file + ".md5"); err == nil {
		sum = strings.Fields(string(b))[0]
	} else {
		f, err := os.Open(file)
		if err != nil {
			t.Fatal(err)
		}
		h := md5.New()
		io.Copy(h, f)
		f.Close()
		sum = hex.EncodeToString(h.Sum(nil))
	}
	url := serveExtract(t, file, sum)
	st := &tallyStore{probe: os.Getenv("ZONES_TEST_TILE"), kinds: map[string]int{}, seen: map[string]bool{}}
	s := NewService(nil, testBase, st)
	dir := t.TempDir()

	start := time.Now()
	if err := s.importExtract(context.Background(), url, dir); err != nil {
		t.Fatal(err)
	}
	state := readState(dir)
	var mem runtime.MemStats
	runtime.ReadMemStats(&mem)
	t.Logf("%d zones, %d tiles in %s (%s); %d MB from the OS, %s",
		state.Zones, state.Tiles, time.Since(start), state.Source, mem.Sys>>20, peakRSS())
	if state.Zones == 0 || state.Tiles != st.tiles {
		t.Fatalf("state %+v, %d tiles saved", state, st.tiles)
	}
	if _, err := os.Stat(filepath.Join(dir, extractFile)); !os.IsNotExist(err) {
		t.Fatal("the extract must be deleted after the import")
	}
	t.Logf("by kind: %v", st.kinds)
	for _, z := range st.kept.Zones {
		t.Logf("%s: %s %s %q", st.probe, z.ID, z.Kind, z.Name)
	}
}
