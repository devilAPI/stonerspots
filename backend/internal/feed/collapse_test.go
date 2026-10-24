package feed_test

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"

	"stonerspots/backend/internal/testutil"
)

type collapsedItem struct {
	ID          uint64 `json:"id"`
	UpdateCount int    `json:"update_count"`
	Spot        struct {
		ID uint64 `json:"id"`
	} `json:"spot"`
}

func feedItems(t *testing.T, _ *sql.DB, h http.Handler, q url.Values) ([]collapsedItem, *string) {
	t.Helper()
	req := httptest.NewRequest("GET", "/feed?"+q.Encode(), nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatalf("feed %d: %s", rec.Code, rec.Body)
	}
	var out struct {
		Items      []collapsedItem `json:"items"`
		NextCursor *string         `json:"next_cursor"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out.Items, out.NextCursor
}

func TestFeedShowsEachSpotOnceWithItsLatestUpdate(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, "lake", 48, 11, 0)
	other := newSpot(t, db, u, "park", 48.1, 11.1, 0)
	first := newUpdate(t, db, s, u, "created", "2026-01-01 10:00:00")
	_ = first
	newUpdate(t, db, s, u, "second", "2026-01-02 10:00:00")
	latest := newUpdate(t, db, s, u, "third", "2026-01-03 10:00:00")
	single := newUpdate(t, db, other, u, "only one", "2026-01-02 12:00:00")

	items, _ := feedItems(t, db, h, url.Values{"sort": {"new"}})
	if len(items) != 2 {
		t.Fatalf("want one card per spot (2), got %d: %+v", len(items), items)
	}
	if items[0].ID != latest || items[0].Spot.ID != s || items[0].UpdateCount != 3 {
		t.Fatalf("first card should be the latest update of the spot with count 3: %+v", items[0])
	}
	if items[1].ID != single || items[1].UpdateCount != 1 {
		t.Fatalf("second card: %+v", items[1])
	}
}

func TestSpotTimelineStillListsAllUpdates(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, "lake", 48, 11, 0)
	for i := 1; i <= 3; i++ {
		newUpdate(t, db, s, u, fmt.Sprintf("u%d", i), fmt.Sprintf("2026-01-0%d 10:00:00", i))
	}
	items, _ := feedItems(t, db, h, url.Values{"sort": {"new"}, "spot_id": {fmt.Sprint(s)}})
	if len(items) != 3 {
		t.Fatalf("the spot page timeline needs every update, got %d", len(items))
	}
}

func TestHiddenLatestUpdateFallsBackToThePreviousOne(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, "lake", 48, 11, 0)
	older := newUpdate(t, db, s, u, "older", "2026-01-01 10:00:00")
	newer := newUpdate(t, db, s, u, "newer", "2026-01-02 10:00:00")
	if _, err := db.Exec(`UPDATE spot_updates SET status='hidden' WHERE id=?`, newer); err != nil {
		t.Fatal(err)
	}
	items, _ := feedItems(t, db, h, url.Values{"sort": {"new"}})
	if len(items) != 1 || items[0].ID != older || items[0].UpdateCount != 1 {
		t.Fatalf("a hidden update must not be the card nor be counted: %+v", items)
	}
}

func TestCollapsedFeedPaginatesWithoutRepeatingSpots(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	want := map[uint64]bool{}
	for i := 0; i < 10; i++ {
		s := newSpot(t, db, u, "lake", 48+float64(i)*0.01, 11, i)
		want[s] = true
		for j := 1; j <= 3; j++ {
			newUpdate(t, db, s, u, "x", fmt.Sprintf("2026-01-%02d 10:00:00", j+i))
		}
	}
	for _, sortName := range []string{"new", "top", "nearby"} {
		seen := map[uint64]int{}
		q := url.Values{"sort": {sortName}, "limit": {"4"}, "lat": {"48"}, "lon": {"11"}}
		for pages := 0; ; pages++ {
			items, next := feedItems(t, db, h, q)
			for _, it := range items {
				seen[it.Spot.ID]++
				if it.UpdateCount != 3 {
					t.Fatalf("%s: update_count %d", sortName, it.UpdateCount)
				}
			}
			if next == nil {
				break
			}
			if pages > 6 {
				t.Fatal("too many pages")
			}
			q.Set("cursor", *next)
		}
		if len(seen) != 10 {
			t.Fatalf("%s: %d spots seen", sortName, len(seen))
		}
		for id, n := range seen {
			if n != 1 || !want[id] {
				t.Fatalf("%s: spot %d appeared %d times", sortName, id, n)
			}
		}
	}
}
