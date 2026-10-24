package admin_test

import (
	"encoding/json"
	"reflect"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestAdminSpotTags(t *testing.T) {
	e := setup(t)
	owner := testutil.NewUser(t, e.db)
	id := newSpot(t, e.db, owner, "Tagged", "active")

	// tags alone count as a changed field
	w := e.patchSpot(t, id, `{"tags":["view","roof","view"]}`)
	e.expect(t, w, 200, "")
	var out struct {
		Title string   `json:"title"`
		Tags  []string `json:"tags"`
	}
	decode(t, w, &out)
	if out.Title != "Tagged" || !reflect.DeepEqual(out.Tags, []string{"roof", "view"}) {
		t.Fatalf("%s", w.Body)
	}
	// replace + combined with another field
	w = e.patchSpot(t, id, `{"title":"Retitled","tags":["lit"]}`)
	e.expect(t, w, 200, "")
	decode(t, w, &out)
	if out.Title != "Retitled" || !reflect.DeepEqual(out.Tags, []string{"lit"}) {
		t.Fatalf("%s", w.Body)
	}
	// untouched when tags omitted
	w = e.patchSpot(t, id, `{"title":"Third"}`)
	decode(t, w, &out)
	if !reflect.DeepEqual(out.Tags, []string{"lit"}) {
		t.Fatalf("%s", w.Body)
	}
	// clear
	w = e.patchSpot(t, id, `{"tags":[]}`)
	e.expect(t, w, 200, "")
	var raw map[string]any
	json.Unmarshal(w.Body.Bytes(), &raw)
	if a, ok := raw["tags"].([]any); !ok || len(a) != 0 {
		t.Fatalf("want []: %s", w.Body)
	}
	// validation; failed patch changes nothing
	e.patchSpot(t, id, `{"tags":["lit"]}`)
	e.expect(t, e.patchSpot(t, id, `{"tags":["bogus"]}`), 400, "invalid_tags")
	e.expect(t, e.patchSpot(t, id, `{"title":"Zzz Zzz","tags":["roof","seating","view","quiet","shade","water","lit","roof"]}`), 400, "invalid_tags")
	e.expect(t, e.patchSpot(t, id, `{"tags":null}`), 400, "invalid_body")
	e.expect(t, e.patchSpot(t, id, `{"tags":"roof"}`), 400, "invalid_body")
	var title string
	e.db.QueryRow(`SELECT title FROM spots WHERE id=?`, id).Scan(&title)
	if title != "Third" {
		t.Fatalf("title changed: %s", title)
	}

	var list struct {
		Items []struct {
			ID   uint64   `json:"id"`
			Tags []string `json:"tags"`
		} `json:"items"`
	}
	other := newSpot(t, e.db, owner, "Untagged", "active")
	w = e.do(t, "GET", "/admin/spots", e.tok)
	decode(t, w, &list)
	got := map[uint64][]string{}
	for _, it := range list.Items {
		got[it.ID] = it.Tags
	}
	if !reflect.DeepEqual(got[id], []string{"lit"}) || got[other] == nil || len(got[other]) != 0 {
		t.Fatalf("list: %s", w.Body)
	}
	var m struct {
		Items []map[string]any `json:"items"`
	}
	json.Unmarshal(w.Body.Bytes(), &m)
	for _, it := range m.Items {
		if _, ok := it["tags"].([]any); !ok {
			t.Fatalf("tags not array: %v", it)
		}
	}
}
