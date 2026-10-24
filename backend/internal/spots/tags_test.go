package spots

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"stonerspots/backend/internal/testutil"
)

func TestNormalizeTags(t *testing.T) {
	if !reflect.DeepEqual(Tags, []string{"roof", "seating", "view", "quiet", "shade", "water", "lit"}) {
		t.Fatalf("Tags = %v", Tags)
	}
	if !ValidTag("roof") || ValidTag("Roof") || ValidTag("") || ValidTag("nope") {
		t.Fatal("ValidTag")
	}
	got, err := NormalizeTags([]string{"lit", "roof", "lit", "view"})
	if err != nil || !reflect.DeepEqual(got, []string{"roof", "view", "lit"}) {
		t.Fatalf("got %v %v", got, err)
	}
	got, err = NormalizeTags(nil)
	if err != nil || got == nil || len(got) != 0 {
		t.Fatalf("nil -> %#v %v", got, err)
	}
	if _, err := NormalizeTags([]string{"roof", "bogus"}); err == nil {
		t.Fatal("unknown must fail")
	}
	// 8 entries (duplicate included) is more than 7 -> error, even if only 7 distinct
	if _, err := NormalizeTags([]string{"roof", "seating", "view", "quiet", "shade", "water", "lit", "roof"}); err == nil {
		t.Fatal(">7 must fail")
	}
	if got, err := NormalizeTags(Tags); err != nil || len(got) != 7 {
		t.Fatalf("all 7: %v %v", got, err)
	}
}

type tagged struct {
	ID     uint64   `json:"id"`
	Tags   []string `json:"tags"`
	Author *struct {
		ID          uint64 `json:"id"`
		DisplayName string `json:"display_name"`
	} `json:"author"`
}

func (e *env) createTagged(t *testing.T, title string, lat, lon float64, tags ...string) tagged {
	t.Helper()
	b, _ := json.Marshal(tags)
	rec := e.do("POST", "/spots", body(title, lat, lon, fmt.Sprintf(`,"force":true,"tags":%s`, b)), true)
	if rec.Code != 201 {
		t.Fatalf("create %s: %d %s", title, rec.Code, rec.Body)
	}
	var s tagged
	json.Unmarshal(rec.Body.Bytes(), &s)
	return s
}

func rawTags(t *testing.T, b []byte) any {
	t.Helper()
	var m map[string]any
	json.Unmarshal(b, &m)
	v, ok := m["tags"]
	if !ok {
		t.Fatalf("no tags key: %s", b)
	}
	return v
}

func TestCreateWithAndWithoutTags(t *testing.T) {
	e := setup(t)
	rec := e.do("POST", "/spots", body("No tags", 52.5, 13.4, ""), true)
	if rec.Code != 201 {
		t.Fatal(rec.Body)
	}
	if v, ok := rawTags(t, rec.Body.Bytes()).([]any); !ok || len(v) != 0 {
		t.Fatalf("want [] got %s", rec.Body)
	}
	s := e.createTagged(t, "With tags", 52.6, 13.5, "view", "roof", "view")
	if !reflect.DeepEqual(s.Tags, []string{"roof", "view"}) {
		t.Fatalf("tags %v", s.Tags)
	}
	var n int
	e.db.QueryRow(`SELECT COUNT(*) FROM spot_tags WHERE spot_id=?`, s.ID).Scan(&n)
	if n != 2 {
		t.Fatalf("rows %d", n)
	}
	for name, tg := range map[string]string{
		"unknown": `["roof","bogus"]`,
		"eight":   `["roof","seating","view","quiet","shade","water","lit","roof"]`,
	} {
		rec := e.do("POST", "/spots", body("Bad "+name, 52.7, 13.6, `,"force":true,"tags":`+tg), true)
		if rec.Code != 400 || errCode(rec) != "invalid_tags" {
			t.Fatalf("%s: %d %s", name, rec.Code, rec.Body)
		}
	}
	e.db.QueryRow(`SELECT COUNT(*) FROM spots WHERE title LIKE 'Bad %'`).Scan(&n)
	if n != 0 {
		t.Fatal("invalid tags must not create a spot")
	}
}

func TestTagsAlwaysArrayEverywhere(t *testing.T) {
	e := setup(t)
	a := e.createTagged(t, "A spot", 52.52, 13.405, "water")
	b := e.createTagged(t, "B spot", 52.53, 13.415)
	chk := func(name string, rec []byte, want map[uint64][]string) {
		var l []tagged
		if err := json.Unmarshal(rec, &l); err != nil {
			t.Fatalf("%s: %v %s", name, err, rec)
		}
		var raw []map[string]any
		json.Unmarshal(rec, &raw)
		for i, s := range l {
			if _, isArr := raw[i]["tags"].([]any); !isArr {
				t.Fatalf("%s: tags not array: %s", name, rec)
			}
			if !reflect.DeepEqual(append([]string{}, s.Tags...), want[s.ID]) {
				t.Fatalf("%s: spot %d tags %v want %v", name, s.ID, s.Tags, want[s.ID])
			}
		}
		if len(l) != 2 {
			t.Fatalf("%s: %d items", name, len(l))
		}
	}
	want := map[uint64][]string{a.ID: {"water"}, b.ID: {}}
	chk("list", e.do("GET", "/spots?south=52&west=13&north=53&east=14", "", false).Body.Bytes(), want)
	chk("nearby", e.do("GET", "/spots/nearby?lat=52.52&lon=13.405&radius_m=5000", "", false).Body.Bytes(), want)
	rec := e.do("GET", fmt.Sprintf("/spots/%d", b.ID), "", false)
	if v, ok := rawTags(t, rec.Body.Bytes()).([]any); !ok || len(v) != 0 {
		t.Fatalf("get: %s", rec.Body)
	}
	// empty list responses stay []
	rec = e.do("GET", "/spots?south=40&west=1&north=41&east=2", "", false)
	if strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Fatalf("%s", rec.Body)
	}
}

// queries reads the server's statement counter of the (single) pooled connection.
func queries(t *testing.T, db *sql.DB) int {
	t.Helper()
	var name string
	var n int
	if err := db.QueryRowContext(context.Background(), `SHOW SESSION STATUS LIKE 'Questions'`).Scan(&name, &n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestTagLoadingIsBatched(t *testing.T) {
	e := setup(t)
	e.db.SetMaxOpenConns(1)
	measure := func() int {
		before := queries(t, e.db)
		rec := e.do("GET", "/spots?south=46&west=6&north=55&east=17&limit=200", "", false)
		if rec.Code != 200 {
			t.Fatal(rec.Body)
		}
		return queries(t, e.db) - before
	}
	for i := 0; i < 5; i++ {
		e.createTagged(t, fmt.Sprintf("spot %d", i), 50+float64(i)*0.01, 10, "roof", "view")
	}
	small := measure()
	for i := 5; i < 150; i++ {
		e.createTagged(t, fmt.Sprintf("spot %d", i), 50+float64(i)*0.01, 10, "roof", "view")
	}
	big := measure()
	if small != big {
		t.Fatalf("query count grows with spots: %d vs %d", small, big)
	}
	rec := e.do("GET", "/spots?south=46&west=6&north=55&east=17&limit=200", "", false)
	var l []tagged
	json.Unmarshal(rec.Body.Bytes(), &l)
	if len(l) != 150 || !reflect.DeepEqual(l[149].Tags, []string{"roof", "view"}) {
		t.Fatalf("%d %v", len(l), l[len(l)-1].Tags)
	}
}

func TestGetHasAuthor(t *testing.T) {
	e := setup(t)
	s := e.create(t, "Authored", 52.5, 13.4)
	rec := e.do("GET", fmt.Sprintf("/spots/%d", s.ID), "", false)
	var g tagged
	json.Unmarshal(rec.Body.Bytes(), &g)
	var name string
	e.db.QueryRow(`SELECT display_name FROM users WHERE id=?`, e.uid).Scan(&name)
	if g.Author == nil || g.Author.ID != e.uid || g.Author.DisplayName != name {
		t.Fatalf("author %+v in %s", g.Author, rec.Body)
	}
}

func (e *env) putTags(spot uint64, tok, b string) (int, string, []byte) {
	rec := e.doTok("PUT", fmt.Sprintf("/spots/%d/tags", spot), b, tok)
	return rec.Code, errCode(rec), rec.Body.Bytes()
}

func TestPutTags(t *testing.T) {
	e := setup(t)
	s := e.createTagged(t, "Taggable", 52.5, 13.4, "roof", "view")
	other := testutil.Token(t, testutil.NewUser(t, e.db))
	adminID := testutil.NewUser(t, e.db)
	e.db.Exec(`UPDATE users SET is_admin=1 WHERE id=?`, adminID)
	adminTok := testutil.Token(t, adminID)

	// replace semantics + 200 full spot object
	code, _, b := e.putTags(s.ID, e.tok, `{"tags":["lit","quiet","lit"]}`)
	if code != 200 {
		t.Fatalf("%d %s", code, b)
	}
	var g tagged
	json.Unmarshal(b, &g)
	if g.ID != s.ID || !reflect.DeepEqual(g.Tags, []string{"quiet", "lit"}) || g.Author == nil || g.Author.ID != e.uid {
		t.Fatalf("%s", b)
	}
	var m map[string]any
	json.Unmarshal(b, &m)
	if m["title"] != "Taggable" {
		t.Fatalf("not full spot: %s", b)
	}
	// clear
	if code, _, b = e.putTags(s.ID, e.tok, `{"tags":[]}`); code != 200 || len(rawTags(t, b).([]any)) != 0 {
		t.Fatalf("%d %s", code, b)
	}
	// other user
	if code, ec, _ := e.putTags(s.ID, other, `{"tags":["lit"]}`); code != 403 || ec != "forbidden" {
		t.Fatalf("other: %d %s", code, ec)
	}
	// admin
	if code, _, b = e.putTags(s.ID, adminTok, `{"tags":["water"]}`); code != 200 {
		t.Fatalf("admin: %d %s", code, b)
	}
	json.Unmarshal(b, &g)
	if !reflect.DeepEqual(g.Tags, []string{"water"}) {
		t.Fatalf("%v", g.Tags)
	}
	// anonymous
	if code, ec, _ := e.putTags(s.ID, "", `{"tags":["lit"]}`); code != 401 {
		t.Fatalf("anon: %d %s", code, ec)
	}
	// invalid
	for _, bad := range []string{`{"tags":["nope"]}`, `{"tags":["roof","seating","view","quiet","shade","water","lit","roof"]}`} {
		if code, ec, _ := e.putTags(s.ID, e.tok, bad); code != 400 || ec != "invalid_tags" {
			t.Fatalf("%s: %d %s", bad, code, ec)
		}
	}
	// failed attempts changed nothing
	json.Unmarshal(e.do("GET", fmt.Sprintf("/spots/%d", s.ID), "", false).Body.Bytes(), &g)
	if !reflect.DeepEqual(g.Tags, []string{"water"}) {
		t.Fatalf("%v", g.Tags)
	}
	// hidden / missing
	e.db.Exec(`UPDATE spots SET status='hidden' WHERE id=?`, s.ID)
	if code, ec, _ := e.putTags(s.ID, e.tok, `{"tags":["lit"]}`); code != 404 || ec != "not_found" {
		t.Fatalf("hidden: %d %s", code, ec)
	}
	if code, ec, _ := e.putTags(99999, e.tok, `{"tags":["lit"]}`); code != 404 || ec != "not_found" {
		t.Fatalf("missing: %d %s", code, ec)
	}
}

func TestTagFilters(t *testing.T) {
	e := setup(t)
	a := e.createTagged(t, "A all", 52.50, 13.40, "roof", "quiet", "water")
	b := e.createTagged(t, "B two", 52.51, 13.41, "roof", "quiet")
	c := e.createTagged(t, "C one", 52.52, 13.42, "roof")
	d := e.createTagged(t, "D none", 52.53, 13.43)
	far := e.createTagged(t, "E far", 48.0, 11.0, "roof", "quiet")
	all := []uint64{a.ID, b.ID, c.ID, d.ID, far.ID}
	get := func(path string) []uint64 {
		t.Helper()
		rec := e.do("GET", path, "", false)
		if rec.Code != 200 {
			t.Fatalf("%s: %d %s", path, rec.Code, rec.Body)
		}
		var l []tagged
		json.Unmarshal(rec.Body.Bytes(), &l)
		m := map[uint64]bool{}
		for _, s := range l {
			m[s.ID] = true
		}
		out := []uint64{}
		for _, id := range all {
			if m[id] {
				out = append(out, id)
			}
		}
		return out
	}
	box := "/spots?south=52&west=13&north=53&east=14"
	cases := []struct {
		q    string
		want []uint64
	}{
		{box + "&tags=roof", []uint64{a.ID, b.ID, c.ID}},
		{box + "&tags=roof,quiet", []uint64{a.ID, b.ID}},
		{box + "&tags=quiet,roof,water", []uint64{a.ID}},
		{box + "&tags=", []uint64{a.ID, b.ID, c.ID, d.ID}},
		{box + "&tags=roof,roof", []uint64{a.ID, b.ID, c.ID}},
		{box + "&tags=roof&category=bench", []uint64{a.ID, b.ID, c.ID}},
		{box + "&tags=roof&category=lake", []uint64{}},
		{"/spots?south=47&west=10&north=49&east=12&tags=roof", []uint64{far.ID}},
		{"/spots/nearby?lat=52.5&lon=13.4&radius_m=5000&tags=roof,quiet", []uint64{a.ID, b.ID}},
		{"/spots/nearby?lat=52.5&lon=13.4&radius_m=5000&tags=water", []uint64{a.ID}},
	}
	for _, tc := range cases {
		if got := get(tc.q); !reflect.DeepEqual(got, tc.want) {
			t.Errorf("%s: got %v want %v", tc.q, got, tc.want)
		}
	}
	for _, q := range []string{box + "&tags=roof,bogus", "/spots/nearby?lat=52.5&lon=13.4&tags=bogus"} {
		rec := e.do("GET", q, "", false)
		if rec.Code != 400 || errCode(rec) != "invalid_tags" {
			t.Errorf("%s: %d %s", q, rec.Code, rec.Body)
		}
	}
}

func TestSpotDeleteCascadesTags(t *testing.T) {
	e := setup(t)
	s := e.createTagged(t, "Doomed", 52.5, 13.4, "roof", "view")
	e.db.Exec(`DELETE FROM spots WHERE id=?`, s.ID)
	var n int
	e.db.QueryRow(`SELECT COUNT(*) FROM spot_tags`).Scan(&n)
	if n != 0 {
		t.Fatalf("%d orphan tag rows", n)
	}
}

func TestBBoxQueryWithTagFilterUsesSpatialIndex(t *testing.T) {
	e := setup(t)
	for i := 0; i < 300; i++ {
		lat, lon := 46+float64(i%30)*0.3, 6+float64(i/30)*1.1
		res, _ := e.db.Exec(`INSERT INTO spots (user_id,title,description,category,location) VALUES (?, 'spot', '', 'bench', POINT(?,?))`, e.uid, lon, lat)
		id, _ := res.LastInsertId()
		if i%3 == 0 {
			e.db.Exec(`INSERT INTO spot_tags (spot_id, tag) VALUES (?, 'roof')`, id)
		}
	}
	e.db.Exec(`ANALYZE TABLE spots`)
	e.db.Exec(`ANALYZE TABLE spot_tags`)
	q, args := bboxQuery(BBox{50, 10, 51, 11}, Filter{Limit: 20, Tags: []string{"roof", "quiet"}})
	rows, err := e.db.QueryContext(context.Background(), "EXPLAIN "+q, args...)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	cols, _ := rows.Columns()
	found := false
	var plan []string
	for rows.Next() {
		vals := make([]sql.RawBytes, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		rows.Scan(ptrs...)
		line := ""
		for i, c := range cols {
			line += c + "=" + string(vals[i]) + " "
			if c == "key" && string(vals[i]) == "idx_spots_location" {
				found = true
			}
		}
		plan = append(plan, line)
	}
	if !found {
		t.Fatalf("EXPLAIN does not use idx_spots_location with tag filter:\n%s", strings.Join(plan, "\n"))
	}
}
