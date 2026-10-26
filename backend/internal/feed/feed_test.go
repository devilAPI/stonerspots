package feed_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/config"
	"stonerspots/backend/internal/feed"
	"stonerspots/backend/internal/quotas"
	"stonerspots/backend/internal/testutil"
)

func setup(t *testing.T) (*sql.DB, http.Handler) {
	t.Helper()
	db := testutil.NewDB(t)
	r := chi.NewRouter()
	feed.Mount(r, app.Deps{DB: db, Cfg: config.Config{JWTSecret: []byte(testutil.JWTSecret), PublicBaseURL: "http://test"}}, quotas.NewTracker(quotas.Config{}))
	return db, r
}

func newSpot(t *testing.T, db *sql.DB, uid uint64, lat, lon float64, likes int) uint64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spots (user_id, title, description, location, like_count) VALUES (?, 'S', '', POINT(?, ?), ?)`,
		uid, lon, lat, likes)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func newPhoto(t *testing.T, db *sql.DB, uid uint64) uint64 {
	t.Helper()
	res, err := db.Exec("INSERT INTO photos (user_id, `key`, thumb_key, width, height) VALUES (?, 'k.jpg', 't.jpg', 10, 10)", uid)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func newUpdate(t *testing.T, db *sql.DB, spot, uid uint64, body, createdAt string) uint64 {
	t.Helper()
	res, err := db.Exec(`INSERT INTO spot_updates (spot_id, user_id, body, created_at) VALUES (?, ?, ?, ?)`, spot, uid, body, createdAt)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

type feedResp struct {
	Items []struct {
		ID     uint64 `json:"id"`
		Body   string `json:"body"`
		Photos []struct {
			ID       uint64 `json:"id"`
			URL      string `json:"url"`
			ThumbURL string `json:"thumb_url"`
		} `json:"photos"`
		Author struct {
			ID          uint64 `json:"id"`
			DisplayName string `json:"display_name"`
		} `json:"author"`
		Spot struct {
			ID        uint64   `json:"id"`
			Lat       float64  `json:"lat"`
			Lon       float64  `json:"lon"`
			LikeCount int      `json:"like_count"`
			Tags      []string `json:"tags"`
		} `json:"spot"`
	} `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

func getFeed(t *testing.T, h http.Handler, q url.Values) (int, feedResp, string) {
	t.Helper()
	req := httptest.NewRequest("GET", "/feed?"+q.Encode(), nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var fr feedResp
	if rec.Code == 200 {
		if err := json.Unmarshal(rec.Body.Bytes(), &fr); err != nil {
			t.Fatal(err)
		}
	}
	return rec.Code, fr, rec.Body.String()
}

func post(t *testing.T, h http.Handler, uid uint64, spot uint64, body any) *httptest.ResponseRecorder {
	t.Helper()
	b, _ := json.Marshal(body)
	req := httptest.NewRequest("POST", fmt.Sprintf("/spots/%d/updates", spot), bytes.NewReader(b))
	req.Header.Set("Authorization", "Bearer "+testutil.Token(t, uid))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestPostUpdateWithPhotos(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	p1, p2 := newPhoto(t, db, u), newPhoto(t, db, u)

	rec := post(t, h, u, s, map[string]any{"body": "nice", "photo_ids": []uint64{p1, p2}})
	if rec.Code != 201 {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var out struct {
		ID     uint64 `json:"id"`
		Photos []struct {
			URL      string `json:"url"`
			ThumbURL string `json:"thumb_url"`
		} `json:"photos"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	if len(out.Photos) != 2 || out.Photos[0].URL != "http://test/api/v1/media/k.jpg" || out.Photos[0].ThumbURL != "http://test/api/v1/media/t.jpg" {
		t.Fatalf("bad photos: %s", rec.Body)
	}
	var n int
	db.QueryRow("SELECT COUNT(*) FROM photos WHERE update_id = ?", out.ID).Scan(&n)
	if n != 2 {
		t.Fatalf("attached %d", n)
	}
	_, fr, _ := getFeed(t, h, url.Values{})
	if len(fr.Items) != 1 || len(fr.Items[0].Photos) != 2 || fr.Items[0].Spot.Lat != 48 || fr.Items[0].Spot.Lon != 11 {
		t.Fatalf("feed: %+v", fr)
	}
	// rejected photos are not served, so they are left out
	db.Exec("UPDATE photos SET status = 'rejected' WHERE id = ?", p2)
	if _, fr, _ = getFeed(t, h, url.Values{}); len(fr.Items[0].Photos) != 1 {
		t.Fatalf("rejected photo listed: %+v", fr.Items[0].Photos)
	}
	// reattaching the same photos fails
	if rec := post(t, h, u, s, map[string]any{"body": "again", "photo_ids": []uint64{p1}}); rec.Code != 400 {
		t.Fatalf("reattach status %d", rec.Code)
	}
	// unauthenticated
	req := httptest.NewRequest("POST", fmt.Sprintf("/spots/%d/updates", s), bytes.NewReader([]byte(`{"body":"x"}`)))
	r2 := httptest.NewRecorder()
	h.ServeHTTP(r2, req)
	if r2.Code != 401 {
		t.Fatalf("unauth status %d", r2.Code)
	}
}

func TestCannotAttachSomeoneElsesPhoto(t *testing.T) {
	db, h := setup(t)
	u, other := testutil.NewUser(t, db), testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	p := newPhoto(t, db, other)

	rec := post(t, h, u, s, map[string]any{"body": "x", "photo_ids": []uint64{p}})
	if rec.Code != 400 || !bytes.Contains(rec.Body.Bytes(), []byte(`"invalid_photo"`)) {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var n int
	db.QueryRow("SELECT COUNT(*) FROM spot_updates").Scan(&n)
	if n != 0 {
		t.Fatalf("update was created despite failure")
	}
	// also via the exported function, plus a mix of own and foreign (atomic)
	own := newPhoto(t, db, u)
	if _, err := feed.CreateUpdate(context.Background(), db, u, s, "x", []uint64{own, p}); err != feed.ErrInvalidPhoto {
		t.Fatalf("err %v", err)
	}
	var upd sql.NullInt64
	db.QueryRow("SELECT update_id FROM photos WHERE id = ?", own).Scan(&upd)
	if upd.Valid {
		t.Fatal("own photo attached despite failure")
	}
	// too many photos
	ids := []uint64{}
	for i := 0; i < 5; i++ {
		ids = append(ids, newPhoto(t, db, u))
	}
	if _, err := feed.CreateUpdate(context.Background(), db, u, s, "x", ids); err != feed.ErrInvalidPhoto {
		t.Fatalf("err %v", err)
	}
}

func TestFeedNewestFirst(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	// one card per spot, so three spots with one update each
	a := newUpdate(t, db, newSpot(t, db, u, 48, 11, 0), u, "a", "2026-01-01 10:00:00")
	b := newUpdate(t, db, newSpot(t, db, u, 48.1, 11, 0), u, "b", "2026-01-03 10:00:00")
	c := newUpdate(t, db, newSpot(t, db, u, 48.2, 11, 0), u, "c", "2026-01-02 10:00:00")
	code, fr, body := getFeed(t, h, url.Values{"sort": {"new"}})
	if code != 200 || len(fr.Items) != 3 || fr.Items[0].ID != b || fr.Items[1].ID != c || fr.Items[2].ID != a {
		t.Fatalf("%d %s", code, body)
	}
	if fr.NextCursor != nil {
		t.Fatal("unexpected cursor")
	}
	if fr.Items[0].Author.DisplayName == "" || fr.Items[0].Photos == nil {
		t.Fatalf("author/photos: %s", body)
	}
}

func TestFeedEmptyIsArray(t *testing.T) {
	_, h := setup(t)
	_, _, body := getFeed(t, h, url.Values{})
	if body != "{\"items\":[],\"next_cursor\":null}\n" {
		t.Fatalf("body %q", body)
	}
}

func TestFeedTopSortsBySpotLikeCount(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	low := newSpot(t, db, u, 48, 11, 1)
	high := newSpot(t, db, u, 48, 11, 9)
	a := newUpdate(t, db, low, u, "a", "2026-01-01 10:00:00")
	b := newUpdate(t, db, high, u, "b", "2026-01-01 10:00:00")
	c := newUpdate(t, db, high, u, "c", "2026-01-01 10:00:00")
	_ = b // superseded by c: the feed shows only the latest update of a spot
	_, fr, body := getFeed(t, h, url.Values{"sort": {"top"}, "limit": {"1"}})
	if len(fr.Items) != 1 || fr.Items[0].ID != c || fr.NextCursor == nil {
		t.Fatal(body)
	}
	_, fr2, body := getFeed(t, h, url.Values{"sort": {"top"}, "limit": {"1"}, "cursor": {*fr.NextCursor}})
	if len(fr2.Items) != 1 || fr2.Items[0].ID != a || fr2.NextCursor != nil {
		t.Fatal(body)
	}
}

func TestFeedNearbyRequiresLatLon(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	near := newSpot(t, db, u, 48.0, 11.0, 0)
	far := newSpot(t, db, u, 50.0, 11.0, 0)
	mid := newSpot(t, db, u, 48.5, 11.0, 0)
	un := newUpdate(t, db, near, u, "n", "2026-01-01 10:00:00")
	uf := newUpdate(t, db, far, u, "f", "2026-01-01 10:00:00")
	um := newUpdate(t, db, mid, u, "m", "2026-01-01 10:00:00")

	if code, _, body := getFeed(t, h, url.Values{"sort": {"nearby"}}); code != 400 {
		t.Fatalf("%d %s", code, body)
	}
	if code, _, _ := getFeed(t, h, url.Values{"sort": {"nearby"}, "lat": {"x"}, "lon": {"11"}}); code != 400 {
		t.Fatal(code)
	}
	q := url.Values{"sort": {"nearby"}, "lat": {"48.01"}, "lon": {"11"}, "limit": {"2"}}
	_, fr, body := getFeed(t, h, q)
	if len(fr.Items) != 2 || fr.Items[0].ID != un || fr.Items[1].ID != um || fr.NextCursor == nil {
		t.Fatal(body)
	}
	q.Set("cursor", *fr.NextCursor)
	_, fr, body = getFeed(t, h, q)
	if len(fr.Items) != 1 || fr.Items[0].ID != uf || fr.NextCursor != nil {
		t.Fatal(body)
	}
}

func TestFeedIgnoresCategoryParamAndHasNoCategory(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s1 := newSpot(t, db, u, 48, 11, 0)
	s2 := newSpot(t, db, u, 48, 11, 0)
	newUpdate(t, db, s1, u, "l", "2026-01-01 10:00:00")
	newUpdate(t, db, s2, u, "b", "2026-01-01 10:00:00")
	for _, c := range []string{"bench", "lake", "forest", "nope"} {
		code, fr, body := getFeed(t, h, url.Values{"category": {c}})
		if code != 200 || len(fr.Items) != 2 {
			t.Fatalf("category=%s: %d %s", c, code, body)
		}
		if strings.Contains(body, "category") {
			t.Fatalf("feed must not contain category: %s", body)
		}
	}
}

func TestCursorPaginationWithIdenticalTimestamps(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	want := map[uint64]bool{}
	for i := 0; i < 25; i++ {
		s := newSpot(t, db, u, 48, 11, 0) // one card per spot
		want[newUpdate(t, db, s, u, "x", "2026-01-01 10:00:00")] = true
	}
	for _, sortName := range []string{"new", "top", "nearby"} {
		seen := map[uint64]int{}
		q := url.Values{"sort": {sortName}, "limit": {"10"}, "lat": {"48"}, "lon": {"11"}}
		pages := 0
		for {
			code, fr, body := getFeed(t, h, q)
			if code != 200 {
				t.Fatalf("%s: %d %s", sortName, code, body)
			}
			for _, it := range fr.Items {
				seen[it.ID]++
			}
			pages++
			if fr.NextCursor == nil {
				break
			}
			q.Set("cursor", *fr.NextCursor)
			if pages > 5 {
				t.Fatal("too many pages")
			}
		}
		if pages != 3 || len(seen) != 25 {
			t.Fatalf("%s: pages %d, unique %d", sortName, pages, len(seen))
		}
		for id, n := range seen {
			if n != 1 || !want[id] {
				t.Fatalf("%s: id %d seen %d times", sortName, id, n)
			}
		}
	}
}

func TestMalformedCursor400(t *testing.T) {
	_, h := setup(t)
	for _, c := range []string{"!!!notbase64", "e30", "bm90anNvbg"} {
		code, _, body := getFeed(t, h, url.Values{"cursor": {c}})
		if code != 400 || !bytes.Contains([]byte(body), []byte(`"invalid_cursor"`)) {
			t.Fatalf("%q: %d %s", c, code, body)
		}
	}
}

func TestHiddenUpdatesExcluded(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, 48, 11, 0)
	hiddenSpot := newSpot(t, db, u, 48, 11, 0)
	vis := newUpdate(t, db, s, u, "v", "2026-01-01 10:00:00")
	hid := newUpdate(t, db, s, u, "h", "2026-01-01 10:00:00")
	newUpdate(t, db, hiddenSpot, u, "hs", "2026-01-01 10:00:00")
	db.Exec("UPDATE spot_updates SET status='hidden' WHERE id = ?", hid)
	db.Exec("UPDATE spots SET status='hidden' WHERE id = ?", hiddenSpot)
	_, fr, body := getFeed(t, h, url.Values{})
	if len(fr.Items) != 1 || fr.Items[0].ID != vis {
		t.Fatal(body)
	}
}
