package zones

import (
	"encoding/json"
	"net/url"
	"strings"
	"testing"
)

func TestTileSnapping(t *testing.T) {
	if got := tileAt(48.137, 11.575); got != (Tile{Y: 2406, X: 578}) {
		t.Fatalf("tileAt = %+v", got)
	}
	// negative coordinates round down, not towards zero
	if got := tileAt(-0.001, -0.001); got != (Tile{Y: -1, X: -1}) {
		t.Fatalf("tileAt negative = %+v", got)
	}
	s, w, n, e := Tile{Y: 2406, X: 578}.Bounds()
	// a box that is exactly one tile (with float noise) is that tile only
	one := bbox{S: s, W: w, N: n, E: e}.tiles()
	if len(one) != 1 || one[0] != (Tile{Y: 2406, X: 578}) {
		t.Fatalf("exact tile box -> %+v", one)
	}
	one = bbox{S: 48.12, W: 11.56, N: 48.14, E: 11.58}.tiles()
	if len(one) != 1 || one[0] != (Tile{Y: 2406, X: 578}) {
		t.Fatalf("decimal tile box -> %+v", one)
	}
	// a box inside one tile is that tile
	if got := (bbox{S: 48.125, W: 11.565, N: 48.13, E: 11.57}).tiles(); len(got) != 1 {
		t.Fatalf("inner box -> %+v", got)
	}
	// crossing edges: 2 rows x 3 columns
	got := bbox{S: 48.135, W: 11.575, N: 48.145, E: 11.615}.tiles()
	if len(got) != 6 || got[0] != (Tile{2406, 578}) || got[5] != (Tile{2407, 580}) {
		t.Fatalf("crossing box -> %+v", got)
	}
	if k := (Tile{Y: 2406, X: 578}).Key(); k != "g2:2406:578" {
		t.Fatalf("key %q", k)
	}
}

func TestParseBBox(t *testing.T) {
	q := func(s, w, n, e string) url.Values {
		return url.Values{"south": {s}, "west": {w}, "north": {n}, "east": {e}}
	}
	ok := []url.Values{
		q("48.12", "11.56", "48.14", "11.58"),
		q("48.10", "11.50", "48.15", "11.58"), // the largest box
	}
	for _, v := range ok {
		if _, err := parseBBox(v); err != nil {
			t.Errorf("%v: %v", v, err)
		}
	}
	bad := []url.Values{
		{},
		q("48.12", "11.56", "48.14", ""),
		q("x", "11.56", "48.14", "11.58"),
		q("NaN", "11.56", "48.14", "11.58"),
		q("48.14", "11.56", "48.12", "11.58"), // south above north
		q("48.12", "11.58", "48.14", "11.56"),
		q("48.10", "11.50", "48.16", "11.52"), // too tall
		q("48.10", "11.50", "48.12", "11.59"), // too wide
		q("-91", "11.50", "-90.99", "11.52"),
		q("48.10", "180", "48.12", "180.01"),
	}
	for _, v := range bad {
		if _, err := parseBBox(v); err == nil {
			t.Errorf("%v: accepted", v)
		}
	}
}

func TestBuildQuery(t *testing.T) {
	q := buildQuery(Tile{Y: 2406, X: 578})
	for _, want := range []string{
		"[out:json][timeout:25]",
		"(48.120000,11.560000,48.140000,11.580000)",
		`nwr["amenity"~"^(school|kindergarten|childcare)$"]`,
		`nwr["building"="kindergarten"]`,
		`["social_facility:for"~"(^|;)(child|juvenile|childcare)(;|$)"]`,
		`["community_centre"="youth_centre"]`,
		`nwr["leisure"="playground"]["access"!~"^(private|no)$"]`,
		"pitch|sports_centre|sports_hall|stadium|track|swimming_pool|water_park|horse_riding|golf_course",
		`nwr["smoking:cannabis"="no"]`,
		`way["highway"="pedestrian"]`,
		`rel["highway"="pedestrian"]`,
		"out body geom qt;",
	} {
		if !strings.Contains(q, want) {
			t.Errorf("query lacks %s:\n%s", want, q)
		}
	}
}

func TestKindOf(t *testing.T) {
	cases := []struct {
		tags map[string]string
		want string
	}{
		{map[string]string{"amenity": "school"}, KindSchool},
		{map[string]string{"amenity": "kindergarten"}, KindKindergarten},
		{map[string]string{"building": "kindergarten"}, KindKindergarten},
		{map[string]string{"amenity": "childcare"}, KindChildcare},
		{map[string]string{"amenity": "social_facility", "social_facility:for": "juvenile"}, KindYouth},
		{map[string]string{"amenity": "social_facility", "social_facility:for": "senior;child"}, KindYouth},
		{map[string]string{"amenity": "social_facility", "social_facility:for": "childcare"}, KindChildcare},
		{map[string]string{"amenity": "social_facility", "social_facility:for": "senior"}, ""},
		{map[string]string{"amenity": "social_facility", "social_facility:for": "children"}, ""},
		{map[string]string{"amenity": "community_centre", "community_centre": "youth_centre"}, KindYouth},
		{map[string]string{"amenity": "community_centre"}, ""},
		{map[string]string{"leisure": "playground"}, KindPlayground},
		{map[string]string{"leisure": "playground", "access": "private"}, ""},
		{map[string]string{"leisure": "pitch"}, KindSports},
		{map[string]string{"leisure": "golf_course", "access": "customers"}, KindSports},
		{map[string]string{"leisure": "swimming_pool", "access": "private"}, ""},
		{map[string]string{"leisure": "sports_hall", "access": "no"}, ""},
		{map[string]string{"leisure": "park"}, ""},
		{map[string]string{"highway": "pedestrian"}, KindPedestrian},
		{map[string]string{"highway": "footway"}, ""},
		{map[string]string{"smoking:cannabis": "no", "highway": "pedestrian"}, KindExplicit},
		{map[string]string{"smoking:cannabis": "no", "amenity": "bar"}, KindExplicit},
		{map[string]string{"smoking:cannabis": "yes", "amenity": "bar"}, ""},
		{map[string]string{"amenity": "school", "leisure": "pitch"}, KindSchool},
		{nil, ""},
	}
	for _, c := range cases {
		if got := kindOf(c.tags); got != c.want {
			t.Errorf("kindOf(%v) = %q, want %q", c.tags, got, c.want)
		}
	}
}

// overpassFixture covers each element shape Overpass returns with out geom.
const overpassFixture = `{
 "version": 0.6, "generator": "Overpass API",
 "elements": [
  {"type":"node","id":1,"lat":48.1301234567,"lon":11.5701234567,"tags":{"amenity":"school","name":" Grundschule Am Test "}},
  {"type":"way","id":2,"geometry":[{"lat":48.125,"lon":11.565},{"lat":48.125,"lon":11.566},{"lat":48.126,"lon":11.566},{"lat":48.126,"lon":11.565},{"lat":48.125,"lon":11.565}],"tags":{"leisure":"playground","name":"Spielplatz Musterweg"}},
  {"type":"way","id":3,"geometry":[{"lat":48.137,"lon":11.570},null,{"lat":48.137,"lon":11.571},{"lat":48.137,"lon":11.572}],"tags":{"highway":"pedestrian","name":"Kaufingerstraße"}},
  {"type":"way","id":4,"geometry":[{"lat":48.138,"lon":11.573},{"lat":48.138,"lon":11.574},{"lat":48.139,"lon":11.574},{"lat":48.138,"lon":11.573}],"tags":{"highway":"pedestrian","area":"yes"}},
  {"type":"way","id":5,"geometry":[{"lat":48.13,"lon":11.57},{"lat":48.131,"lon":11.57}],"tags":{"amenity":"parking"}},
  {"type":"relation","id":6,"tags":{"type":"multipolygon","leisure":"pitch"},"members":[
    {"type":"way","ref":61,"role":"outer","geometry":[{"lat":48.121,"lon":11.561},{"lat":48.121,"lon":11.562},{"lat":48.122,"lon":11.562}]},
    {"type":"way","ref":62,"role":"outer","geometry":[{"lat":48.121,"lon":11.561},{"lat":48.122,"lon":11.561},{"lat":48.122,"lon":11.562}]},
    {"type":"way","ref":63,"role":"inner","geometry":[{"lat":48.1213,"lon":11.5613},{"lat":48.1213,"lon":11.5614},{"lat":48.1214,"lon":11.5614},{"lat":48.1213,"lon":11.5613}]}
  ]},
  {"type":"relation","id":7,"tags":{"type":"site","amenity":"school"},"members":[
    {"type":"way","ref":71,"role":"","geometry":[{"lat":48.131,"lon":11.561},{"lat":48.131,"lon":11.562},{"lat":48.132,"lon":11.562},{"lat":48.131,"lon":11.561}]},
    {"type":"way","ref":72,"role":"","geometry":[{"lat":48.133,"lon":11.561},{"lat":48.133,"lon":11.562},{"lat":48.134,"lon":11.562},{"lat":48.133,"lon":11.561}]},
    {"type":"node","ref":73,"role":"entrance","lat":48.13,"lon":11.56}
  ]},
  {"type":"node","id":8,"lat":48.1,"lon":11.5,"tags":{"amenity":"bar","smoking:cannabis":"no"}}
 ]
}`

func TestParseOverpass(t *testing.T) {
	zones, err := parseOverpass(strings.NewReader(overpassFixture))
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]Zone{}
	for _, z := range zones {
		byID[z.ID] = z
	}
	if len(zones) != 7 {
		t.Fatalf("got %d zones, want 7 (parking dropped): %+v", len(zones), zones)
	}
	check := func(id, kind, name, typ, coords string) {
		t.Helper()
		z, ok := byID[id]
		if !ok {
			t.Fatalf("%s missing", id)
		}
		if z.Kind != kind || z.Name != name || z.Geometry.Type != typ {
			t.Errorf("%s = %s %q %s, want %s %q %s", id, z.Kind, z.Name, z.Geometry.Type, kind, name, typ)
		}
		if coords != "" && string(z.Geometry.Coordinates) != coords {
			t.Errorf("%s coords = %s, want %s", id, z.Geometry.Coordinates, coords)
		}
	}
	check("node/1", KindSchool, "Grundschule Am Test", "Point", "[48.130123,11.570123]")
	check("way/2", KindPlayground, "Spielplatz Musterweg", "Polygon",
		"[[[48.125,11.565],[48.125,11.566],[48.126,11.566],[48.126,11.565],[48.125,11.565]]]")
	// the middle point lies on the line: simplified away; null skipped
	check("way/3", KindPedestrian, "Kaufingerstraße", "LineString", "[[48.137,11.57],[48.137,11.572]]")
	check("way/4", KindPedestrian, "", "Polygon", "")
	// two half rings joined into one ring; the inner ring is dropped
	check("relation/6", KindSports, "", "Polygon", "")
	check("relation/7", KindSchool, "", "MultiPolygon", "")
	check("node/8", KindExplicit, "", "Point", "")

	if byID["way/3"].AccessHours != "7-20" || byID["way/4"].AccessHours != "7-20" {
		t.Errorf("pedestrian zones need access_hours")
	}
	if byID["way/2"].AccessHours != "" {
		t.Errorf("only pedestrian zones have access_hours")
	}
	var rings [][][2]float64
	if err := json.Unmarshal(byID["relation/6"].Geometry.Coordinates, &rings); err != nil {
		t.Fatal(err)
	}
	if len(rings) != 1 || len(rings[0]) != 5 || rings[0][0] != rings[0][4] {
		t.Errorf("relation ring = %v", rings)
	}
}

func TestParseOverpassRemarkFails(t *testing.T) {
	body := `{"elements":[{"type":"node","id":1,"lat":1,"lon":1,"tags":{"amenity":"school"}}],
		"remark":"runtime error: Query timed out in \"query\" at line 3 after 26 seconds."}`
	if _, err := parseOverpass(strings.NewReader(body)); err == nil {
		t.Fatal("a cut-short answer must not count as data")
	}
	if _, err := parseOverpass(strings.NewReader("<html>busy</html>")); err == nil {
		t.Fatal("non-JSON accepted")
	}
}

func TestSimplify(t *testing.T) {
	// 1 m sideways wiggle on a 100 m line goes, 5 m stays (1e-5° lat ≈ 1.1 m)
	line := []pt{{48, 11}, {48.00001, 11.0005}, {48, 11.001}, {48.00005, 11.0015}, {48, 11.002}}
	got := simplify(line, simplifyTolerance)
	want := []pt{{48, 11}, {48, 11.001}, {48.00005, 11.0015}, {48, 11.002}}
	if len(got) != len(want) {
		t.Fatalf("simplify = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("simplify = %v, want %v", got, want)
		}
	}
	// a ring stays closed and keeps its corners
	sq := []pt{{48, 11}, {48, 11.0005}, {48, 11.001}, {48.001, 11.001}, {48.001, 11}, {48, 11}}
	r := simplify(sq, simplifyTolerance)
	if len(r) != 5 || r[0] != r[len(r)-1] {
		t.Fatalf("ring = %v", r)
	}
	// a tiny ring is kept as it is rather than collapsing
	tiny := []pt{{48, 11}, {48, 11.000001}, {48.000001, 11.000001}, {48, 11}}
	if r := simplify(tiny, simplifyTolerance); len(r) != 4 {
		t.Fatalf("tiny ring = %v", r)
	}
}
