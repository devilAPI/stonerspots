package zones

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

// Places on both sides of the border, checked against the full-resolution
// OSM boundary before simplification.
var germanyCases = []struct {
	name     string
	lat, lon float64
	in       bool
}{
	{"Munich", 48.1374, 11.5755, true},
	{"Berlin", 52.52, 13.405, true},
	{"Lörrach", 47.6156, 7.6614, true},
	{"Weil am Rhein", 47.5947, 7.6206, true},
	{"Kehl", 48.5726, 7.8153, true},
	{"Freilassing", 47.8406, 12.9772, true},
	{"Konstanz", 47.6603, 9.1758, true},
	{"Görlitz", 51.1526, 14.9872, true},
	{"Frankfurt (Oder)", 52.3471, 14.5506, true},
	{"Flensburg", 54.7836, 9.4321, true},
	{"Helgoland", 54.1817, 7.8856, true},
	{"Büsingen (exclave)", 47.6967, 8.6900, true},
	{"Aachen", 50.7753, 6.0839, true},
	{"Westerland (Sylt)", 54.9079, 8.3105, true},
	{"Garmisch", 47.4917, 11.0955, true},
	{"Passau", 48.5667, 13.4319, true},
	{"Basel", 47.5596, 7.5886, false},
	{"Strasbourg", 48.5734, 7.7521, false},
	{"Salzburg", 47.8095, 13.0550, false},
	{"Kreuzlingen", 47.6447, 9.1772, false},
	{"Słubice", 52.3497, 14.5603, false},
	{"Schaffhausen", 47.6973, 8.6349, false},
	{"Vaals", 50.7703, 6.0186, false},
	{"Zgorzelec", 51.1500, 15.0083, false},
	{"Jungholz (AT)", 47.5747, 10.4486, false},
	{"Riezlern (AT)", 47.3583, 10.1856, false},
	{"Vienna", 48.2082, 16.3738, false},
	{"Paris", 48.8566, 2.3522, false},
	{"Copenhagen", 55.6761, 12.5683, false},
	{"Prague", 50.0755, 14.4378, false},
	{"Porto", 41.1373, -8.6094, false},
	{"Sydney", -33.8688, 151.2093, false},
}

func TestInGermany(t *testing.T) {
	for _, c := range germanyCases {
		if got := InGermany(c.lat, c.lon); got != c.in {
			t.Errorf("%s (%v, %v): InGermany = %v, want %v", c.name, c.lat, c.lon, got, c.in)
		}
	}
}

func TestGermanyOverlap(t *testing.T) {
	cases := []struct {
		name string
		t    Tile
		want Overlap
	}{
		{"Munich", tileAt(48.1374, 11.5755), Inside},
		{"Vienna", tileAt(48.2082, 16.3738), Outside},
		{"Porto", tileAt(41.1373, -8.6094), Outside},
		{"Konstanz/Kreuzlingen", Tile{2382, 458}, Partly},
		{"Büsingen", tileAt(47.6967, 8.6900), Partly},
	}
	for _, c := range cases {
		s, w, n, e := c.t.Bounds()
		if got := GermanyOverlap(s, w, n, e); got != c.want {
			t.Errorf("%s: overlap = %v, want %v", c.name, got, c.want)
		}
	}
	// a box around all of Germany holds the border
	if got := GermanyOverlap(40, 0, 60, 20); got != Partly {
		t.Errorf("Europe: %v", got)
	}
}

func TestPolylineRoundTrip(t *testing.T) {
	for _, line := range strings.Split(germanyBorderData, "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if got := EncodePolyline(DecodePolyline(line)); got != line {
			t.Fatalf("round trip changed a ring (%d -> %d bytes)", len(line), len(got))
		}
	}
	pts := []pt{{38.5, -120.2}, {40.7, -120.95}, {43.252, -126.453}}
	// Google's documented example
	if got := EncodePolyline(pts); got != "_p~iF~ps|U_ulLnnqC_mqNvxq`@" {
		t.Errorf("encode = %q", got)
	}
}

// The app ships the same rings (germany_border.g.dart); both come from
// cmd/germanyborder and must not drift apart.
func TestAppHasSameBorder(t *testing.T) {
	b, err := os.ReadFile("../../../app/lib/features/zones/germany_border.g.dart")
	if os.IsNotExist(err) {
		t.Skip("app sources not checked out")
	}
	if err != nil {
		t.Fatal(err)
	}
	var dart []string
	for _, m := range regexp.MustCompile(`(?m)^  r'([^']*)',$`).FindAllStringSubmatch(string(b), -1) {
		dart = append(dart, m[1])
	}
	var goRings []string
	for _, line := range strings.Split(germanyBorderData, "\n") {
		if line != "" && !strings.HasPrefix(line, "#") {
			goRings = append(goRings, line)
		}
	}
	if len(goRings) == 0 || strings.Join(dart, "\n") != strings.Join(goRings, "\n") {
		t.Fatalf("app border (%d rings) differs from backend border (%d rings): rerun cmd/germanyborder",
			len(dart), len(goRings))
	}
}
