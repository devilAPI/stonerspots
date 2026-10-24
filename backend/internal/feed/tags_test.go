package feed_test

import (
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"net/url"
	"reflect"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestFeedSpotCarriesTagsAndFilters(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	// 25 matching items (spot with roof+quiet), 10 with only roof, 5 with none.
	both := newSpot(t, db, u, "bench", 48, 11, 1)
	roofOnly := newSpot(t, db, u, "bench", 48.1, 11.1, 2)
	none := newSpot(t, db, u, "bench", 48.2, 11.2, 3)
	db.Exec(`INSERT INTO spot_tags (spot_id, tag) VALUES (?, 'roof'), (?, 'quiet'), (?, 'roof')`, both, both, roofOnly)
	for i := 0; i < 25; i++ {
		newUpdate(t, db, both, u, fmt.Sprintf("b%d", i), fmt.Sprintf("2026-01-01 10:%02d:00", i))
	}
	for i := 0; i < 10; i++ {
		newUpdate(t, db, roofOnly, u, fmt.Sprintf("r%d", i), fmt.Sprintf("2026-01-01 11:%02d:00", i))
	}
	for i := 0; i < 5; i++ {
		newUpdate(t, db, none, u, fmt.Sprintf("n%d", i), fmt.Sprintf("2026-01-01 12:%02d:00", i))
	}

	for _, sort := range []string{"new", "top", "nearby"} {
		seen := map[uint64]bool{}
		cursor := ""
		pages := 0
		for {
			q := url.Values{"tags": {"roof,quiet"}, "limit": {"10"}, "sort": {sort}, "lat": {"48"}, "lon": {"11"}}
			if cursor != "" {
				q.Set("cursor", cursor)
			}
			code, fr, raw := getFeed(t, h, q)
			if code != 200 {
				t.Fatalf("%s: %d %s", sort, code, raw)
			}
			pages++
			for _, it := range fr.Items {
				if seen[it.ID] {
					t.Fatalf("%s: duplicate item %d", sort, it.ID)
				}
				seen[it.ID] = true
				if it.Spot.ID != both {
					t.Fatalf("%s: item of spot %d leaked through filter", sort, it.Spot.ID)
				}
				if !reflect.DeepEqual(it.Spot.Tags, []string{"roof", "quiet"}) {
					t.Fatalf("%s: spot tags %v", sort, it.Spot.Tags)
				}
			}
			if fr.NextCursor == nil {
				break
			}
			cursor = *fr.NextCursor
			if pages > 5 {
				t.Fatal("too many pages")
			}
		}
		if len(seen) != 25 || pages != 3 {
			t.Fatalf("%s: got %d items in %d pages", sort, len(seen), pages)
		}
	}

	// single tag
	_, fr, _ := getFeed(t, h, url.Values{"tags": {"roof"}, "limit": {"50"}})
	if len(fr.Items) != 35 {
		t.Fatalf("roof: %d", len(fr.Items))
	}
	// no filter: spots without tags carry [] not null
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/feed?limit=50", nil))
	var raw struct {
		Items []struct {
			Spot map[string]any `json:"spot"`
		} `json:"items"`
	}
	json.Unmarshal(rec.Body.Bytes(), &raw)
	if len(raw.Items) != 40 {
		t.Fatalf("unfiltered %d", len(raw.Items))
	}
	for _, it := range raw.Items {
		if _, ok := it.Spot["tags"].([]any); !ok {
			t.Fatalf("tags must be an array: %v", it.Spot)
		}
	}
	// empty param = no filter; combined with category; unknown = 400
	if _, fr, _ := getFeed(t, h, url.Values{"tags": {""}, "limit": {"50"}}); len(fr.Items) != 40 {
		t.Fatalf("empty param: %d", len(fr.Items))
	}
	if _, fr, _ := getFeed(t, h, url.Values{"tags": {"quiet"}, "category": {"lake"}}); len(fr.Items) != 0 {
		t.Fatalf("category+tags: %d", len(fr.Items))
	}
	if _, fr, _ := getFeed(t, h, url.Values{"tags": {"quiet"}, "category": {"bench"}, "limit": {"50"}}); len(fr.Items) != 25 {
		t.Fatalf("category+tags: %d", len(fr.Items))
	}
	code, _, body := getFeed(t, h, url.Values{"tags": {"roof,bogus"}})
	if code != 400 {
		t.Fatalf("unknown tag: %d %s", code, body)
	}
	var e struct{ Error struct{ Code string } }
	json.Unmarshal([]byte(body), &e)
	if e.Error.Code != "invalid_tags" {
		t.Fatalf("code %q", e.Error.Code)
	}
}

func TestPostedUpdateItemHasTagsArray(t *testing.T) {
	db, h := setup(t)
	u := testutil.NewUser(t, db)
	s := newSpot(t, db, u, "lake", 48, 11, 0)
	db.Exec(`INSERT INTO spot_tags (spot_id, tag) VALUES (?, 'view'), (?, 'lit')`, s, s)
	rec := post(t, h, u, s, map[string]any{"body": "hi"})
	var out struct {
		Spot struct {
			Tags []string `json:"tags"`
		} `json:"spot"`
	}
	json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 201 || !reflect.DeepEqual(out.Spot.Tags, []string{"view", "lit"}) {
		t.Fatalf("%d %s", rec.Code, rec.Body)
	}
}
