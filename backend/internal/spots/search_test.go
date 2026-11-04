package spots

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
	"testing"
)

func (e *env) search(t *testing.T, query string) []Spot {
	t.Helper()
	rec := e.do("GET", "/spots/search?"+query, "", false)
	if rec.Code != 200 {
		t.Fatalf("search %s: %d %s", query, rec.Code, rec.Body)
	}
	var out []Spot
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func titles(list []Spot) []string {
	out := make([]string, len(list))
	for i, s := range list {
		out[i] = s.Title
	}
	return out
}

func TestSearchValidation(t *testing.T) {
	e := setup(t)
	for _, q := range []string{"", "q=", "q=a", "q=%20%20a%20%20", "q=" + strings.Repeat("x", 81)} {
		rec := e.do("GET", "/spots/search?"+q, "", false)
		if rec.Code != 400 || errCode(rec) != "invalid_query" {
			t.Errorf("%q: %d %s", q, rec.Code, rec.Body)
		}
	}
	for _, q := range []string{"q=park&lat=52", "q=park&lon=13", "q=park&lat=x&lon=13", "q=park&lat=95&lon=13"} {
		rec := e.do("GET", "/spots/search?"+q, "", false)
		if rec.Code != 400 || errCode(rec) != "invalid_location" {
			t.Errorf("%q: %d %s", q, rec.Code, rec.Body)
		}
	}
	// 80 characters (umlauts count as one) are fine; no match is an empty array
	rec := e.do("GET", "/spots/search?q="+url.QueryEscape(strings.Repeat("ä", 80)), "", false)
	if rec.Code != 200 || strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Fatalf("%d %q", rec.Code, rec.Body)
	}
}

func TestSearchMatchesCaseAndAccentInsensitive(t *testing.T) {
	e := setup(t)
	a := e.create(t, "Schöne Bank am Fluss", 52.52, 13.405)
	b := e.create(t, "Stadtpark Wiese", 48.2, 16.37)
	e.create(t, "Ganz woanders", 47.37, 8.54)

	for q, want := range map[string]uint64{
		"q=SCHONE":            a.ID,
		"q=sch%C3%B6ne":       a.ID,
		"q=bank+am":           a.ID,
		"q=%20+fluss+":        a.ID,
		"q=PARK":              b.ID,
		"q=stadtpark%20wiese": b.ID,
	} {
		got := e.search(t, q)
		if len(got) != 1 || got[0].ID != want {
			t.Errorf("%s: %v", q, titles(got))
		}
		if len(got) == 1 && (got[0].Tags == nil || got[0].DistanceM != nil) {
			t.Errorf("%s: tags %v distance %v", q, got[0].Tags, got[0].DistanceM)
		}
	}
	// wildcards in the query match literally
	if got := e.search(t, "q="+url.QueryEscape("%%")); len(got) != 0 {
		t.Errorf("%%%%: %v", titles(got))
	}
	if got := e.search(t, "q="+url.QueryEscape("__")); len(got) != 0 {
		t.Errorf("__: %v", titles(got))
	}
	e.create(t, "100% Chill_Zone", 52.0, 13.0)
	if got := e.search(t, "q="+url.QueryEscape("0% chill_")); len(got) != 1 {
		t.Errorf("literal: %v", titles(got))
	}
}

func TestSearchSkipsHiddenSpots(t *testing.T) {
	e := setup(t)
	a := e.create(t, "Versteckter Ort", 52.52, 13.405)
	e.create(t, "Sichtbarer Ort", 52.53, 13.405)
	if _, err := e.db.Exec(`UPDATE spots SET status = 'hidden' WHERE id = ?`, a.ID); err != nil {
		t.Fatal(err)
	}
	got := e.search(t, "q=ort")
	if len(got) != 1 || got[0].Title != "Sichtbarer Ort" {
		t.Fatalf("%v", titles(got))
	}
}

func TestSearchOrderWithoutLocation(t *testing.T) {
	e := setup(t)
	sub := e.create(t, "Alter Parkplatz", 52.50, 13.40) // substring, word prefix
	mid := e.create(t, "Kleinparkanlage", 52.51, 13.40) // substring only
	pre := e.create(t, "Parkbank", 52.52, 13.40)        // title prefix
	exact := e.create(t, "Park", 52.53, 13.40)          // exact
	low := e.create(t, "Unterpark", 52.54, 13.40)       // substring only, newer, unrated
	e.review(t, mid.ID, 5, "active")

	got := e.search(t, "q=park")
	want := []uint64{exact.ID, pre.ID, sub.ID, mid.ID, low.ID}
	if len(got) != len(want) {
		t.Fatalf("%v", titles(got))
	}
	for i := range want {
		if got[i].ID != want[i] {
			t.Fatalf("order %v", titles(got))
		}
	}
	if got[3].RatingAvg != 5 || got[3].RatingCount != 1 {
		t.Fatalf("rating %+v", got[3])
	}
}

func TestSearchNearestFirstWithLocation(t *testing.T) {
	e := setup(t)
	far := e.create(t, "Park Wien", 48.2082, 16.3738)
	near := e.create(t, "Stadtpark Berlin", 52.52, 13.405)
	mid := e.create(t, "Park Leipzig", 51.34, 12.37)

	got := e.search(t, "q=park&lat=52.5&lon=13.4")
	want := []uint64{near.ID, mid.ID, far.ID}
	if len(got) != 3 {
		t.Fatalf("%v", titles(got))
	}
	for i := range want {
		if got[i].ID != want[i] {
			t.Fatalf("order %v", titles(got))
		}
		if got[i].DistanceM == nil {
			t.Fatalf("missing distance on %s", got[i].Title)
		}
	}
	if d := *got[0].DistanceM; d < 1000 || d > 3000 {
		t.Fatalf("distance %v", d)
	}
}

func TestSearchCapsResults(t *testing.T) {
	e := setup(t)
	for i := 0; i < searchLimit+5; i++ {
		e.create(t, fmt.Sprintf("Wiese %d", i), 50+float64(i)*0.01, 10)
	}
	if got := e.search(t, "q=wiese"); len(got) != searchLimit {
		t.Fatalf("len %d", len(got))
	}
	if got := e.search(t, "q=wiese&lat=50&lon=10"); len(got) != searchLimit || got[0].Title != "Wiese 0" {
		t.Fatalf("len %d first %v", len(got), titles(got)[:1])
	}
}
