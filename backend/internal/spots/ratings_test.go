package spots

import (
	"encoding/json"
	"fmt"
	"testing"

	"stonerspots/backend/internal/testutil"
)

type ratedSpot struct {
	ID          uint64  `json:"id"`
	RatingAvg   float64 `json:"rating_avg"`
	RatingCount int     `json:"rating_count"`
}

func (e *env) review(t *testing.T, spot uint64, rating int, status string) uint64 {
	t.Helper()
	u := testutil.NewUser(t, e.db)
	res, err := e.db.Exec(`INSERT INTO spot_reviews (spot_id, user_id, rating, body, status) VALUES (?, ?, ?, '', ?)`, spot, u, rating, status)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return uint64(id)
}

func TestRatingFieldsEverywhere(t *testing.T) {
	e := setup(t)
	a := e.create(t, "Rated spot", 52.52, 13.405)
	b := e.create(t, "Unrated spot", 52.53, 13.415)
	e.review(t, a.ID, 5, "active")
	e.review(t, a.ID, 4, "active")
	e.review(t, a.ID, 4, "active")
	hidden := e.review(t, a.ID, 1, "hidden")

	check := func(name string, rs []ratedSpot) {
		t.Helper()
		got := map[uint64]ratedSpot{}
		for _, r := range rs {
			got[r.ID] = r
		}
		if got[a.ID].RatingCount != 3 || got[a.ID].RatingAvg != 4.3 {
			t.Fatalf("%s rated: %+v", name, got[a.ID])
		}
		if r, ok := got[b.ID]; !ok || r.RatingCount != 0 || r.RatingAvg != 0 {
			t.Fatalf("%s unrated: %+v", name, got[b.ID])
		}
	}
	rec := e.do("GET", "/spots?south=52&west=13&north=53&east=14", "", false)
	var l []ratedSpot
	json.Unmarshal(rec.Body.Bytes(), &l)
	check("list", l)
	rec = e.do("GET", "/spots/nearby?lat=52.52&lon=13.405&radius_m=5000", "", false)
	l = nil
	json.Unmarshal(rec.Body.Bytes(), &l)
	check("nearby", l)
	rec = e.do("GET", fmt.Sprintf("/spots/%d", a.ID), "", false)
	var one ratedSpot
	json.Unmarshal(rec.Body.Bytes(), &one)
	check("get", []ratedSpot{one, {ID: b.ID}})
	// raw JSON must carry the keys even when zero
	rec = e.do("GET", fmt.Sprintf("/spots/%d", b.ID), "", false)
	var raw map[string]any
	json.Unmarshal(rec.Body.Bytes(), &raw)
	if _, ok := raw["rating_avg"]; !ok {
		t.Fatalf("missing rating_avg: %s", rec.Body)
	}
	if _, ok := raw["rating_count"]; !ok {
		t.Fatalf("missing rating_count: %s", rec.Body)
	}
	// create response
	rec = e.do("POST", "/spots", body("Fresh two", 52.60, 13.5, ""), true)
	raw = nil
	json.Unmarshal(rec.Body.Bytes(), &raw)
	if _, ok := raw["rating_count"]; !ok || rec.Code != 201 {
		t.Fatalf("create response: %s", rec.Body)
	}
	// hiding/deleting changes aggregates immediately
	e.db.Exec(`UPDATE spot_reviews SET status='hidden' WHERE spot_id=? AND rating=5`, a.ID)
	rec = e.do("GET", fmt.Sprintf("/spots/%d", a.ID), "", false)
	json.Unmarshal(rec.Body.Bytes(), &one)
	if one.RatingCount != 2 || one.RatingAvg != 4 {
		t.Fatalf("after hide: %+v", one)
	}
	e.db.Exec(`DELETE FROM spot_reviews WHERE id=?`, hidden)
	e.db.Exec(`DELETE FROM spot_reviews WHERE spot_id=?`, a.ID)
	rec = e.do("GET", fmt.Sprintf("/spots/%d", a.ID), "", false)
	one = ratedSpot{}
	json.Unmarshal(rec.Body.Bytes(), &one)
	if one.RatingCount != 0 || one.RatingAvg != 0 {
		t.Fatalf("after delete: %+v", one)
	}
}
