package spots

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/testutil"
)

type env struct {
	db  *sql.DB
	h   http.Handler
	uid uint64
	tok string
}

func setup(t *testing.T) *env {
	t.Helper()
	db := testutil.NewDB(t)
	cfg := config.Config{JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://x.test"}
	r := chi.NewRouter()
	Mount(r, app.Deps{DB: db, Cfg: cfg})
	uid := testutil.NewUser(t, db)
	return &env{db: db, h: r, uid: uid, tok: testutil.Token(t, uid)}
}

func (e *env) do(method, path, body string, auth bool) *httptest.ResponseRecorder {
	if auth {
		return e.doTok(method, path, body, e.tok)
	}
	return e.doTok(method, path, body, "")
}

func (e *env) doTok(method, path, body, tok string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if tok != "" {
		req.Header.Set("Authorization", "Bearer "+tok)
	}
	rec := httptest.NewRecorder()
	e.h.ServeHTTP(rec, req)
	return rec
}

func body(title string, lat, lon float64, extra string) string {
	return fmt.Sprintf(`{"title":%q,"description":"d","lat":%v,"lon":%v%s}`, title, lat, lon, extra)
}

func (e *env) create(t *testing.T, title string, lat, lon float64) Spot {
	t.Helper()
	rec := e.do("POST", "/spots", body(title, lat, lon, `,"force":true`), true)
	if rec.Code != 201 {
		t.Fatalf("create %s: %d %s", title, rec.Code, rec.Body)
	}
	var s Spot
	json.Unmarshal(rec.Body.Bytes(), &s)
	return s
}

func errCode(rec *httptest.ResponseRecorder) string {
	var b struct{ Error struct{ Code string } }
	json.Unmarshal(rec.Body.Bytes(), &b)
	return b.Error.Code
}

func TestCreateAndGetSpot(t *testing.T) {
	e := setup(t)
	rec := e.do("POST", "/spots", body("Bank am Fluss", 52.52, 13.405, ""), true)
	if rec.Code != 201 {
		t.Fatalf("got %d %s", rec.Code, rec.Body)
	}
	var s Spot
	json.Unmarshal(rec.Body.Bytes(), &s)
	if s.ID == 0 || s.Lat != 52.52 || s.Lon != 13.405 || s.Title != "Bank am Fluss" {
		t.Fatalf("bad spot %+v", s)
	}
	e.db.Exec(`INSERT INTO spot_updates (spot_id, user_id, body) VALUES (?,?, 'x')`, s.ID, e.uid)
	e.db.Exec("INSERT INTO photos (user_id, `key`, thumb_key, width, height, update_id) VALUES (?, 'a/b.jpg', 'a/t.jpg', 1,1, 1)", e.uid)
	rec = e.do("GET", fmt.Sprintf("/spots/%d", s.ID), "", false)
	if rec.Code != 200 {
		t.Fatalf("get %d %s", rec.Code, rec.Body)
	}
	var m map[string]any
	json.Unmarshal(rec.Body.Bytes(), &m)
	if m["cover_url"] != "http://x.test/api/v1/media/a/b.jpg" {
		t.Fatalf("cover_url %v", m["cover_url"])
	}
	if _, ok := m["distance_m"]; ok {
		t.Fatal("distance_m must be omitted")
	}
	for _, k := range []string{"id", "title", "description", "lat", "lon", "like_count", "created_at"} {
		if _, ok := m[k]; !ok {
			t.Fatalf("missing %s", k)
		}
	}
	if _, ok := m["category"]; ok {
		t.Fatal("category must not be present")
	}
	if e.do("GET", "/spots/9999", "", false).Code != 404 {
		t.Fatal("want 404")
	}
}

func TestCreateValidation(t *testing.T) {
	e := setup(t)
	for name, b := range map[string]string{
		"short title": `{"title":"ab","description":"","lat":52.5,"lon":13.4}`,
		"long desc":   fmt.Sprintf(`{"title":"abc","description":%q,"lat":52.5,"lon":13.4}`, strings.Repeat("a", 1001)),
	} {
		if rec := e.do("POST", "/spots", b, true); rec.Code != 400 {
			t.Errorf("%s: %d", name, rec.Code)
		}
	}
}

func TestRejectsOutOfRangeAndSwappedCoordinates(t *testing.T) {
	e := setup(t)
	for _, c := range [][2]float64{{200, 13.4}, {52.5, 190}, {13.405, 52.52}} {
		rec := e.do("POST", "/spots", body("Test spot", c[0], c[1], ""), true)
		if rec.Code != 400 || errCode(rec) != "invalid_location" {
			t.Errorf("%v: %d %s", c, rec.Code, rec.Body)
		}
	}
	rec := e.do("POST", "/spots", `{"title":"abc","description":""}`, true)
	if rec.Code != 400 || errCode(rec) != "invalid_location" {
		t.Errorf("missing coords: %d %s", rec.Code, rec.Body)
	}
}

func TestRejectsOutsideRegion(t *testing.T) {
	e := setup(t)
	for _, c := range [][2]float64{{48.8566, 2.3522}, {40, -30}} {
		rec := e.do("POST", "/spots", body("Test spot", c[0], c[1], ""), true)
		if rec.Code != 400 || errCode(rec) != "invalid_location" {
			t.Errorf("%v: %d %s", c, rec.Code, rec.Body)
		}
	}
	for _, c := range [][2]float64{{52.52, 13.405}, {48.2082, 16.3738}} {
		if rec := e.do("POST", "/spots", body("Test spot", c[0], c[1], ""), true); rec.Code != 201 {
			t.Errorf("%v: %d %s", c, rec.Code, rec.Body)
		}
	}
}

func TestInvertedBBox400(t *testing.T) {
	e := setup(t)
	rec := e.do("GET", "/spots?south=53&west=13&north=52&east=14", "", false)
	if rec.Code != 400 || errCode(rec) != "invalid_bbox" {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	if rec := e.do("GET", "/spots?south=1&west=1", "", false); rec.Code != 400 {
		t.Fatalf("missing params: %d", rec.Code)
	}
}

func TestHugeBBoxIsCappedToLimit(t *testing.T) {
	e := setup(t)
	for i := 0; i < 5; i++ {
		e.create(t, fmt.Sprintf("Spot %d", i), 50+float64(i)*0.1, 10)
	}
	var out []Spot
	rec := e.do("GET", "/spots?south=-90&west=-180&north=90&east=180&limit=3", "", false)
	json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 200 || len(out) != 3 {
		t.Fatalf("%d len=%d", rec.Code, len(out))
	}
	rec = e.do("GET", "/spots?south=-90&west=-180&north=90&east=180&limit=5000", "", false)
	if rec.Code != 200 {
		t.Fatalf("%d", rec.Code)
	}
}

func TestEmptyBBoxReturnsEmptyArray(t *testing.T) {
	e := setup(t)
	for _, q := range []string{"south=50&west=10&north=51&east=11", "south=50&west=10&north=50&east=11"} {
		rec := e.do("GET", "/spots?"+q, "", false)
		if rec.Code != 200 || strings.TrimSpace(rec.Body.String()) != "[]" {
			t.Fatalf("%s: %d %q", q, rec.Code, rec.Body)
		}
	}
	rec := e.do("GET", "/spots/nearby?lat=50&lon=10", "", false)
	if strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Fatalf("nearby %q", rec.Body)
	}
}

func TestBBoxOrdersByLikeCountThenID(t *testing.T) {
	e := setup(t)
	a := e.create(t, "Alpha", 50.0, 10.0)
	b := e.create(t, "Bravo", 50.1, 10.1)
	c := e.create(t, "Charlie", 50.2, 10.2)
	d := e.create(t, "Delta", 50.3, 10.3)
	e.db.Exec(`UPDATE spots SET like_count=5 WHERE id IN (?,?)`, c.ID, d.ID)
	e.db.Exec(`UPDATE spots SET like_count=9 WHERE id=?`, b.ID)
	var out []Spot
	rec := e.do("GET", "/spots?south=49&west=9&north=51&east=11", "", false)
	json.Unmarshal(rec.Body.Bytes(), &out)
	want := []uint64{b.ID, c.ID, d.ID, a.ID}
	if len(out) != 4 {
		t.Fatalf("len %d", len(out))
	}
	for i := range want {
		if out[i].ID != want[i] {
			t.Fatalf("order %v", out)
		}
	}
	// The category query param no longer exists: ignored, no filtering, no 400.
	rec = e.do("GET", "/spots?south=49&west=9&north=51&east=11&category=river", "", false)
	var ign []Spot
	json.Unmarshal(rec.Body.Bytes(), &ign)
	if rec.Code != 200 || len(ign) != 4 {
		t.Fatalf("category param must be ignored: %d %q", rec.Code, rec.Body)
	}
}

func TestStrayCategoryKeyIsIgnoredAndNeverReturned(t *testing.T) {
	e := setup(t)
	rec := e.do("POST", "/spots", `{"title":"Old client","description":"","category":"bench","lat":52.52,"lon":13.405,"tags":["seating"]}`, true)
	if rec.Code != 201 || strings.Contains(rec.Body.String(), "category") {
		t.Fatalf("create: %d %s", rec.Code, rec.Body)
	}
	for _, p := range []string{
		"/spots?south=52&west=13&north=53&east=14&category=lake",
		"/spots/nearby?lat=52.52&lon=13.405&radius_m=5000&category=lake",
	} {
		rec = e.do("GET", p, "", false)
		if rec.Code != 200 || strings.Contains(rec.Body.String(), "category") || !strings.Contains(rec.Body.String(), "Old client") {
			t.Fatalf("%s: %d %s", p, rec.Code, rec.Body)
		}
	}
	rec = e.do("GET", "/spots/1", "", false)
	if rec.Code != 200 || strings.Contains(rec.Body.String(), "category") {
		t.Fatalf("get: %d %s", rec.Code, rec.Body)
	}
}

func TestNearbyOrdersByDistance(t *testing.T) {
	e := setup(t)
	far := e.create(t, "Far", 52.54, 13.405)
	near := e.create(t, "Near", 52.521, 13.405)
	e.create(t, "Outside", 52.7, 13.405)
	var out []Spot
	rec := e.do("GET", "/spots/nearby?lat=52.52&lon=13.405&radius_m=5000", "", false)
	json.Unmarshal(rec.Body.Bytes(), &out)
	if len(out) != 2 || out[0].ID != near.ID || out[1].ID != far.ID {
		t.Fatalf("%s", rec.Body)
	}
	if out[0].DistanceM == nil || *out[0].DistanceM < 100 || *out[0].DistanceM > 120 {
		t.Fatalf("distance %v", out[0].DistanceM)
	}
	if rec := e.do("GET", "/spots/nearby?lat=200&lon=13", "", false); rec.Code != 400 || errCode(rec) != "invalid_location" {
		t.Fatalf("%d", rec.Code)
	}
}

func TestDuplicateWithin25mReturns409WithExistingID(t *testing.T) {
	e := setup(t)
	s := e.create(t, "Original", 52.52, 13.405)
	rec := e.do("POST", "/spots", body("Copy", 52.52005, 13.405, ""), true) // ~5.5 m
	if rec.Code != 409 || errCode(rec) != "possible_duplicate" {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
	var b struct {
		ExistingID uint64 `json:"existing_id"`
	}
	json.Unmarshal(rec.Body.Bytes(), &b)
	if b.ExistingID != s.ID {
		t.Fatalf("existing_id %d want %d", b.ExistingID, s.ID)
	}
	if rec := e.do("POST", "/spots", body("Far copy", 52.5206, 13.405, ""), true); rec.Code != 201 { // ~67 m
		t.Fatalf("%d", rec.Code)
	}
}

func TestForceCreatesDuplicate(t *testing.T) {
	e := setup(t)
	e.create(t, "Original", 52.52, 13.405)
	if rec := e.do("POST", "/spots", body("Copy", 52.52005, 13.405, `,"force":true`), true); rec.Code != 201 {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
}

func TestHiddenSpotsAreExcluded(t *testing.T) {
	e := setup(t)
	s := e.create(t, "Hidden one", 52.52, 13.405)
	e.db.Exec(`UPDATE spots SET status='hidden' WHERE id=?`, s.ID)
	if e.do("GET", fmt.Sprintf("/spots/%d", s.ID), "", false).Code != 404 {
		t.Fatal("get hidden")
	}
	if b := e.do("GET", "/spots?south=52&west=13&north=53&east=14", "", false).Body.String(); strings.TrimSpace(b) != "[]" {
		t.Fatalf("bbox %q", b)
	}
	if b := e.do("GET", "/spots/nearby?lat=52.52&lon=13.405", "", false).Body.String(); strings.TrimSpace(b) != "[]" {
		t.Fatalf("nearby %q", b)
	}
	// hidden spots do not trigger duplicate detection
	if rec := e.do("POST", "/spots", body("Again", 52.52, 13.405, ""), true); rec.Code != 201 {
		t.Fatalf("dup vs hidden: %d", rec.Code)
	}
}

func TestCreateRequiresAuth(t *testing.T) {
	e := setup(t)
	if rec := e.do("POST", "/spots", body("Test spot", 52.52, 13.405, ""), false); rec.Code != 401 {
		t.Fatalf("%d", rec.Code)
	}
}

func TestBBoxQueryUsesSpatialIndex(t *testing.T) {
	e := setup(t)
	for i := 0; i < 300; i++ {
		lat, lon := 46+float64(i%30)*0.3, 6+float64(i/30)*1.1
		e.db.Exec(`INSERT INTO spots (user_id,title,description,location) VALUES (?, 'spot', '', POINT(?,?))`, e.uid, lon, lat)
	}
	e.db.Exec(`ANALYZE TABLE spots`)
	q, args := bboxQuery(BBox{50, 10, 51, 11}, Filter{Limit: 20})
	rows, err := e.db.QueryContext(context.Background(), "EXPLAIN "+q, args...)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	cols, _ := rows.Columns()
	found := false
	for rows.Next() {
		vals := make([]sql.RawBytes, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		rows.Scan(ptrs...)
		for i, c := range cols {
			if c == "key" && string(vals[i]) == "idx_spots_location" {
				found = true
			}
		}
	}
	if !found {
		t.Fatal("EXPLAIN does not use idx_spots_location")
	}
}
