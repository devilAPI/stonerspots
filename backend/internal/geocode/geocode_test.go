package geocode

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
	"stonerspots/backend/internal/testutil"
)

type fake struct {
	srv  *httptest.Server
	hits atomic.Int32
	last atomic.Pointer[http.Request]
	body atomic.Pointer[string]
	code atomic.Int32
}

func newFake(t *testing.T, body string) *fake {
	t.Helper()
	f := &fake{}
	f.body.Store(&body)
	f.code.Store(200)
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		f.hits.Add(1)
		f.last.Store(r)
		w.WriteHeader(int(f.code.Load()))
		fmt.Fprint(w, *f.body.Load())
	}))
	t.Cleanup(f.srv.Close)
	return f
}

const oneHit = `[{"display_name":"Marienplatz 1, 80331 München, Bayern, Deutschland","lat":"48.1374","lon":"11.5755"}]`

func deps(f *fake) app.Deps {
	return app.Deps{Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret), GeocoderURL: f.srv.URL}}
}

// setupWith uses the real Mount (default limiter) when interval < 0.
func setupWith(t *testing.T, f *fake, interval time.Duration) http.Handler {
	t.Helper()
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) {
		if interval < 0 {
			Mount(r, deps(f))
		} else {
			mount(r, deps(f), interval, 2*time.Second)
		}
	})
	return r
}

func setup(t *testing.T, f *fake) http.Handler { return setupWith(t, f, time.Millisecond) }

func get(h http.Handler, uid uint64, t *testing.T, q string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest("GET", "/api/v1/geocode?q="+url.QueryEscape(q), nil)
	if uid != 0 {
		req.Header.Set("Authorization", "Bearer "+testutil.Token(t, uid))
	}
	w := httptest.NewRecorder()
	h.ServeHTTP(w, req)
	return w
}

type resp struct {
	Results []struct {
		Label string  `json:"label"`
		Lat   float64 `json:"lat"`
		Lon   float64 `json:"lon"`
	} `json:"results"`
}

func errCode(t *testing.T, w *httptest.ResponseRecorder) string {
	t.Helper()
	var e struct{ Error struct{ Code string } }
	_ = json.Unmarshal(w.Body.Bytes(), &e)
	return e.Error.Code
}

func TestHappyPath(t *testing.T) {
	f := newFake(t, oneHit)
	w := get(setup(t, f), 1, t, "  Marienplatz München ")
	if w.Code != 200 {
		t.Fatalf("code %d %s", w.Code, w.Body)
	}
	var r resp
	_ = json.Unmarshal(w.Body.Bytes(), &r)
	if len(r.Results) != 1 || r.Results[0].Label != "Marienplatz 1, 80331 München, Bayern, Deutschland" ||
		r.Results[0].Lat != 48.1374 || r.Results[0].Lon != 11.5755 {
		t.Fatalf("bad results %s", w.Body)
	}
	req := f.last.Load()
	if req.URL.Path != "/search" {
		t.Fatalf("path %s", req.URL.Path)
	}
	want := map[string]string{"format": "jsonv2", "q": "Marienplatz München", "limit": "5",
		"countrycodes": "de,at,ch,li", "accept-language": "de"}
	got := req.URL.Query()
	for k, v := range want {
		if got.Get(k) != v {
			t.Errorf("param %s=%q want %q", k, got.Get(k), v)
		}
	}
	if len(got) != len(want) {
		t.Errorf("unexpected params %v", got)
	}
	if ua := req.Header.Get("User-Agent"); ua != "stonerspots/0.1 (+https://github.com/devilAPI/stonerspots)" {
		t.Errorf("UA %q", ua)
	}
}

func TestBadCoordsSkippedAndMax5(t *testing.T) {
	items := []string{`{"display_name":"bad","lat":"x","lon":"1"}`, `{"display_name":"bad2","lat":"1","lon":""}`}
	for i := 0; i < 8; i++ {
		items = append(items, fmt.Sprintf(`{"display_name":"p%d","lat":"%d.5","lon":"10.25"}`, i, 40+i))
	}
	f := newFake(t, "["+strings.Join(items, ",")+"]")
	w := get(setup(t, f), 1, t, "abc")
	var r resp
	_ = json.Unmarshal(w.Body.Bytes(), &r)
	if len(r.Results) != 5 || r.Results[0].Label != "p0" || r.Results[0].Lat != 40.5 {
		t.Fatalf("got %s", w.Body)
	}
}

func TestEmptyIsArray(t *testing.T) {
	f := newFake(t, `[]`)
	w := get(setup(t, f), 1, t, "nowhere")
	if strings.TrimSpace(w.Body.String()) != `{"results":[]}` {
		t.Fatalf("got %s", w.Body)
	}
}

func TestQueryLength(t *testing.T) {
	f := newFake(t, `[]`)
	h := setup(t, f)
	for _, q := range []string{"ab", "   ", "  a  ", strings.Repeat("x", 201), ""} {
		w := get(h, 1, t, q)
		if w.Code != 400 || errCode(t, w) != "invalid_query" {
			t.Errorf("q=%q: %d %s", q, w.Code, w.Body)
		}
	}
	if w := get(h, 1, t, strings.Repeat("ü", 200)); w.Code != 200 {
		t.Errorf("200 runes should pass: %d", w.Code)
	}
	if w := get(h, 1, t, "abc"); w.Code != 200 {
		t.Errorf("3 chars should pass: %d", w.Code)
	}
	if f.hits.Load() != 2 {
		t.Errorf("upstream hits %d", f.hits.Load())
	}
}

func TestUnauthenticated(t *testing.T) {
	f := newFake(t, `[]`)
	if w := get(setup(t, f), 0, t, "berlin"); w.Code != 401 {
		t.Fatalf("code %d", w.Code)
	}
}

func TestCache(t *testing.T) {
	f := newFake(t, oneHit)
	h := setup(t, f)
	get(h, 1, t, "Marienplatz   München")
	w := get(h, 2, t, "  marienplatz münchen ")
	if w.Code != 200 || f.hits.Load() != 1 || !strings.Contains(w.Body.String(), "Marienplatz 1") {
		t.Fatalf("code %d hits %d", w.Code, f.hits.Load())
	}
}

func TestUserRateLimit(t *testing.T) {
	f := newFake(t, oneHit)
	h := setup(t, f)
	for i := 1; i <= 20; i++ {
		if w := get(h, 1, t, "same query"); w.Code != 200 {
			t.Fatalf("req %d: %d", i, w.Code)
		}
	}
	w := get(h, 1, t, "same query")
	if w.Code != 429 || errCode(t, w) != "rate_limited" {
		t.Fatalf("21st: %d %s", w.Code, w.Body)
	}
	if w := get(h, 2, t, "same query"); w.Code != 200 {
		t.Fatalf("other user: %d", w.Code)
	}
}

func TestUpstreamFailuresNotCached(t *testing.T) {
	f := newFake(t, `boom`)
	f.code.Store(500)
	h := setup(t, f)
	w := get(h, 1, t, "berlin")
	if w.Code != 502 || errCode(t, w) != "geocoder_unavailable" {
		t.Fatalf("500: %d %s", w.Code, w.Body)
	}
	f.code.Store(200)
	if w = get(h, 1, t, "berlin"); w.Code != 502 {
		t.Fatalf("garbage: %d", w.Code)
	}
	body := oneHit
	f.body.Store(&body)
	if w = get(h, 1, t, "berlin"); w.Code != 200 {
		t.Fatalf("recovery: %d", w.Code)
	}
	if f.hits.Load() != 3 {
		t.Fatalf("hits %d", f.hits.Load())
	}
}

func TestUpstreamUnreachable(t *testing.T) {
	f := newFake(t, `[]`)
	h := setup(t, f)
	f.srv.Close()
	if w := get(h, 1, t, "berlin"); w.Code != 502 {
		t.Fatalf("code %d", w.Code)
	}
}

func TestGlobalLimiterSpacesRequests(t *testing.T) {
	f := newFake(t, `[]`)
	h := setupWith(t, f, 100*time.Millisecond)
	start := time.Now()
	get(h, 1, t, "first")
	get(h, 1, t, "second")
	if d := time.Since(start); d < 100*time.Millisecond {
		t.Fatalf("not spaced: %v", d)
	}
}

func TestGlobalLimiterBusy(t *testing.T) {
	f := newFake(t, `[]`)
	r := chi.NewRouter()
	r.Route("/api/v1", func(r chi.Router) { mount(r, deps(f), time.Hour, 10*time.Millisecond) })
	if w := get(r, 1, t, "first"); w.Code != 200 {
		t.Fatalf("first %d", w.Code)
	}
	w := get(r, 1, t, "second")
	if w.Code != 503 || errCode(t, w) != "geocoder_busy" {
		t.Fatalf("second %d %s", w.Code, w.Body)
	}
}

func TestDefaultLimiter(t *testing.T) {
	f := newFake(t, `[]`)
	h := setupWith(t, f, -1)
	start := time.Now()
	get(h, 1, t, "first")
	get(h, 1, t, "second")
	d := time.Since(start)
	if d < 900*time.Millisecond || f.hits.Load() != 2 {
		t.Fatalf("default 1s spacing not applied: %v hits %d", d, f.hits.Load())
	}
}
