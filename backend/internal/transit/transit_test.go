package transit

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
)

// overpass fakes the Overpass API; it answers body and records queries.
type overpass struct {
	srv     *httptest.Server
	hits    atomic.Int32
	query   atomic.Pointer[string]
	body    string
	code    int
	delayed time.Duration
}

func newOverpass(t *testing.T, body string) *overpass {
	t.Helper()
	o := &overpass{body: body, code: 200}
	o.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		o.hits.Add(1)
		if r.Header.Get("User-Agent") == "" || r.Method != http.MethodPost {
			w.WriteHeader(400)
			return
		}
		r.ParseForm()
		q := r.PostForm.Get("data")
		o.query.Store(&q)
		time.Sleep(o.delayed)
		w.WriteHeader(o.code)
		fmt.Fprint(w, o.body)
	}))
	t.Cleanup(o.srv.Close)
	return o
}

func setup(o *overpass, wait time.Duration) http.Handler {
	r := chi.NewRouter()
	mount(r, app.Deps{Cfg: config.Config{OverpassURL: o.srv.URL}}, time.Millisecond, wait)
	return r
}

func get(h http.Handler, bbox string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest("GET", "/transit/stops?bbox="+url.QueryEscape(bbox), nil))
	return w
}

func decode(t *testing.T, w *httptest.ResponseRecorder) []Stop {
	t.Helper()
	var r struct{ Stops []Stop }
	if err := json.Unmarshal(w.Body.Bytes(), &r); err != nil {
		t.Fatalf("%s: %v", w.Body, err)
	}
	return r.Stops
}

// Munich centre, around Marienplatz.
const munich = "11.551,48.121,11.599,48.149"

const elements = `{"elements":[
 {"type":"node","id":1,"lat":48.1374,"lon":11.5755,"tags":{"railway":"station","station":"subway","name":"Marienplatz"}},
 {"type":"node","id":2,"lat":48.1372,"lon":11.5757,"tags":{"public_transport":"station","subway":"yes","name":"Marienplatz"}},
 {"type":"node","id":3,"lat":48.1402,"lon":11.5600,"tags":{"railway":"station","name":"München Hbf"}},
 {"type":"way","id":4,"center":{"lat":48.1405,"lon":11.5605},"tags":{"public_transport":"station","train":"yes","name":"München Hbf"}},
 {"type":"node","id":5,"lat":48.1350,"lon":11.5800,"tags":{"railway":"tram_stop","name":"Isartor"}},
 {"type":"node","id":6,"lat":48.1352,"lon":11.5803,"tags":{"railway":"tram_stop","name":"Isartor"}},
 {"type":"node","id":7,"lat":48.1300,"lon":11.5700,"tags":{"highway":"bus_stop","name":"Sendlinger Tor"}},
 {"type":"node","id":8,"lat":48.1301,"lon":11.5900,"tags":{"highway":"bus_stop"}},
 {"type":"node","id":9,"lat":48.1301,"lon":11.5910,"tags":{"highway":"bus_stop"}},
 {"type":"node","id":10,"lat":48.1450,"lon":11.5650,"tags":{"railway":"station","disused":"yes","name":"Old"}},
 {"type":"node","id":11,"lat":48.1250,"lon":11.5950,"tags":{"amenity":"ferry_terminal","name":"Fähre"}},
 {"type":"node","id":12,"lat":49.0000,"lon":11.5650,"tags":{"railway":"station","name":"Far away"}}
]}`

func TestStopsClassifiedAndMerged(t *testing.T) {
	o := newOverpass(t, elements)
	h := setup(o, time.Second)
	w := get(h, munich)
	if w.Code != 200 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if !strings.Contains(*o.query.Load(), `"highway"="bus_stop"`) {
		t.Fatalf("query %s", *o.query.Load())
	}
	got := map[string]int{}
	for _, s := range decode(t, w) {
		got[s.Kind+":"+s.Name]++
	}
	want := map[string]int{
		"subway:Marienplatz": 1, // node + station node merged
		"train:München Hbf":  1, // node + area merged
		"tram:Isartor":       1, // both directions merged
		"bus:Sendlinger Tor": 1,
		"bus:":               2, // unnamed stops are never merged
		"ferry:Fähre":        1,
	}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("got %v\nwant %v", got, want) // disused and out-of-box left out
	}
	if w.Header().Get("Cache-Control") != "public, max-age=3600" {
		t.Fatal(w.Header())
	}
}

func TestStopsCachedPerCell(t *testing.T) {
	o := newOverpass(t, elements)
	h := setup(o, time.Second)
	get(h, munich)
	// the same area, and a part of it, come from the cache
	get(h, munich)
	if w := get(h, "11.56,48.13,11.58,48.14"); len(decode(t, w)) == 0 {
		t.Fatal("no stops from cache")
	}
	if n := o.hits.Load(); n != 1 {
		t.Fatalf("upstream hits %d", n)
	}
	// a box reaching into new cells asks only for those
	get(h, "11.551,48.121,11.649,48.149")
	if n := o.hits.Load(); n != 2 {
		t.Fatalf("upstream hits %d", n)
	}
	if q := *o.query.Load(); !strings.Contains(q, "[bbox:48.100000,11.600000,48.150000,11.650000]") {
		t.Fatalf("query %s", q)
	}
}

func TestStopsErrors(t *testing.T) {
	o := newOverpass(t, elements)
	h := setup(o, time.Second)
	for _, bbox := range []string{"", "1,2,3", "x,48,11,49", "11.6,48.1,11.5,48.2", "11,48,200,49"} {
		if w := get(h, bbox); w.Code != 400 {
			t.Fatalf("%q: %d", bbox, w.Code)
		}
	}
	if w := get(h, "11,48,11.6,48.4"); w.Code != 400 || !strings.Contains(w.Body.String(), "bbox_too_large") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}

	o.code = 504
	if w := get(h, munich); w.Code != 502 || !strings.Contains(w.Body.String(), "transit_unavailable") {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	// failures are not cached
	o.code = 200
	if w := get(h, munich); w.Code != 200 || len(decode(t, w)) == 0 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
}

func TestStopsBusyWhileUpstreamSlow(t *testing.T) {
	o := newOverpass(t, elements)
	o.delayed = 300 * time.Millisecond
	h := setup(o, 50*time.Millisecond)
	done := make(chan int)
	go func() { done <- get(h, munich).Code }()
	time.Sleep(50 * time.Millisecond)
	if w := get(h, "9.0,47.0,9.05,47.05"); w.Code != 503 {
		t.Fatalf("second query while busy: %d", w.Code)
	}
	if c := <-done; c != 200 {
		t.Fatalf("first query: %d", c)
	}
}

// A fetch caches exactly the cells it asked for: the fetched box's edges
// touch the neighbouring cells, which must not be cached empty.
func TestFetchCachesOnlyItsCells(t *testing.T) {
	o := newOverpass(t, elements)
	c := newClient(o.srv.URL, time.Millisecond, time.Second)
	if _, err := c.Stops(t.Context(), BBox{S: 48.131, W: 11.561, N: 48.139, E: 11.569}); err != nil {
		t.Fatal(err)
	}
	if n := len(c.cache); n != 1 {
		t.Fatalf("cached %d cells for a one-cell box", n)
	}
}
