package zones

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strings"
)

// Kinds of zone. Everything but pedestrian is forbidden within sight, which
// § 5 KCanG takes as given within 100 m (the app draws that buffer);
// pedestrian zones only between 7 and 20 h.
const (
	KindSchool       = "school"
	KindKindergarten = "kindergarten"
	KindChildcare    = "childcare"
	KindYouth        = "youth"
	KindPlayground   = "playground"
	KindSports       = "sports"
	KindExplicit     = "explicit" // smoking:cannabis=no on the place itself
	KindPedestrian   = "pedestrian"
)

// PedestrianHours is when consumption is forbidden in pedestrian zones.
const PedestrianHours = "7-20"

// Zone is one place as the API returns it.
type Zone struct {
	ID          string   `json:"id"`
	Kind        string   `json:"kind"`
	Name        string   `json:"name,omitempty"`
	Geometry    Geometry `json:"geometry"`
	AccessHours string   `json:"access_hours,omitempty"`
}

// Geometry is GeoJSON-like, but with [lat, lon] pairs: Point [lat, lon],
// LineString [[lat, lon], ...], Polygon [ring] (outer ring only, closed),
// MultiPolygon [[ring], ...].
type Geometry struct {
	Type        string          `json:"type"`
	Coordinates json.RawMessage `json:"coordinates"`
}

type pt = [2]float64 // lat, lon

// sportsLeisure are the leisure values taken as sports facilities.
var sportsLeisure = []string{"pitch", "sports_centre", "sports_hall", "stadium", "track",
	"swimming_pool", "water_park", "horse_riding", "golf_course"}

// youthFor are social_facility:for values meaning children or young people.
var youthFor = []string{"child", "juvenile", "childcare"}

// buildQuery is the Overpass QL for the box s, w, n, e (a block). `out
// geom` returns the coordinates with every way and relation member, so no
// node lookups are needed.
func buildQuery(s, w, n, e float64) string {
	bb := fmt.Sprintf("(%.6f,%.6f,%.6f,%.6f)", s, w, n, e)
	// § 5 Abs. 2 KCanG: sports facilities count only when publicly
	// accessible (Nr. 4); playgrounds always (Nr. 2), also the private one
	// of a block of flats
	notPrivate := `["access"!~"^(private|no)$"]`
	lines := []string{
		`nwr["amenity"~"^(school|kindergarten|childcare)$"]` + bb + `;`,
		`nwr["building"="kindergarten"]` + bb + `;`,
		`nwr["amenity"="social_facility"]["social_facility:for"~"(^|;)(` + strings.Join(youthFor, "|") + `)(;|$)"]` + bb + `;`,
		`nwr["amenity"="community_centre"]["community_centre"="youth_centre"]` + bb + `;`,
		`nwr["leisure"="playground"]` + bb + `;`,
		`nwr["leisure"~"^(` + strings.Join(sportsLeisure, "|") + `)$"]` + notPrivate + bb + `;`,
		`nwr["smoking:cannabis"="no"]` + bb + `;`,
		`way["highway"="pedestrian"]` + bb + `;`,
		`rel["highway"="pedestrian"]` + bb + `;`,
	}
	return fmt.Sprintf("[out:json][timeout:%d];\n(\n  %s\n);\nout body geom qt;\n",
		int(queryTimeout.Seconds()), strings.Join(lines, "\n  "))
}

func hasValue(list, v string) bool {
	for _, p := range strings.Split(list, ";") {
		if strings.TrimSpace(p) == v {
			return true
		}
	}
	return false
}

func publicAccess(tags map[string]string) bool {
	a := tags["access"]
	return a != "private" && a != "no"
}

// kindOf maps OSM tags to a zone kind ("" = not a zone). An explicit
// smoking:cannabis=no wins over everything else.
func kindOf(tags map[string]string) string {
	if tags["smoking:cannabis"] == "no" {
		return KindExplicit
	}
	switch tags["amenity"] {
	case "school":
		return KindSchool
	case "kindergarten":
		return KindKindergarten
	case "childcare":
		return KindChildcare
	case "social_facility":
		f := tags["social_facility:for"]
		if hasValue(f, "childcare") {
			return KindChildcare
		}
		if hasValue(f, "child") || hasValue(f, "juvenile") {
			return KindYouth
		}
	case "community_centre":
		if tags["community_centre"] == "youth_centre" {
			return KindYouth
		}
	}
	if tags["building"] == "kindergarten" {
		return KindKindergarten
	}
	if tags["leisure"] == "playground" {
		return KindPlayground
	}
	if l := tags["leisure"]; l != "" && publicAccess(tags) {
		for _, s := range sportsLeisure {
			if l == s {
				return KindSports
			}
		}
	}
	if tags["highway"] == "pedestrian" {
		return KindPedestrian
	}
	return ""
}

// Overpass JSON (only the fields we read). Points in a geometry can be null
// when Overpass clips; they are skipped.
type osmPoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

type osmMember struct {
	Type     string      `json:"type"`
	Role     string      `json:"role"`
	Lat      *float64    `json:"lat"`
	Lon      *float64    `json:"lon"`
	Geometry []*osmPoint `json:"geometry"`
}

type osmElement struct {
	Type     string            `json:"type"`
	ID       int64             `json:"id"`
	Lat      *float64          `json:"lat"`
	Lon      *float64          `json:"lon"`
	Tags     map[string]string `json:"tags"`
	Geometry []*osmPoint       `json:"geometry"`
	Members  []osmMember       `json:"members"`
}

type osmResponse struct {
	Remark   string       `json:"remark"`
	Elements []osmElement `json:"elements"`
}

// parseOverpass turns an Overpass answer into zones. A "remark" means the
// query was cut short (timeout, out of memory): the elements are incomplete,
// so the whole answer counts as failed rather than being cached.
func parseOverpass(r io.Reader) ([]Zone, error) {
	var res osmResponse
	if err := json.NewDecoder(r).Decode(&res); err != nil {
		return nil, fmt.Errorf("overpass: decode: %w", err)
	}
	if res.Remark != "" {
		return nil, fmt.Errorf("overpass: %s", res.Remark)
	}
	zones := make([]Zone, 0, len(res.Elements))
	for _, el := range res.Elements {
		if z, ok := zoneOf(el); ok {
			zones = append(zones, z)
		}
	}
	return zones, nil
}

func zoneOf(el osmElement) (Zone, bool) {
	kind := kindOf(el.Tags)
	if kind == "" {
		return Zone{}, false
	}
	g, ok := geometryOf(el, kind)
	if !ok {
		return Zone{}, false
	}
	z := Zone{ID: el.Type + "/" + fmt.Sprint(el.ID), Kind: kind, Name: strings.TrimSpace(el.Tags["name"]), Geometry: g}
	if kind == KindPedestrian {
		z.AccessHours = PedestrianHours
	}
	return z, true
}

func points(geom []*osmPoint) []pt {
	out := make([]pt, 0, len(geom))
	for _, p := range geom {
		if p != nil {
			out = append(out, pt{p.Lat, p.Lon})
		}
	}
	return out
}

func closed(line []pt) bool { return len(line) >= 4 && line[0] == line[len(line)-1] }

func geometryOf(el osmElement, kind string) (Geometry, bool) {
	switch el.Type {
	case "node":
		if el.Lat == nil || el.Lon == nil {
			return Geometry{}, false
		}
		return encode("Point", round(pt{*el.Lat, *el.Lon}))
	case "way":
		line := points(el.Geometry)
		if len(line) < 2 {
			return Geometry{}, false
		}
		// A closed pedestrian way is a loop of street unless it says
		// area=yes; closed amenity/leisure ways are areas.
		if closed(line) && (kind != KindPedestrian || el.Tags["area"] == "yes") {
			return encode("Polygon", [][]pt{roundAll(simplify(line, simplifyTolerance))})
		}
		return encode("LineString", roundAll(simplify(line, simplifyTolerance)))
	case "relation":
		return relationGeometry(el)
	}
	return Geometry{}, false
}

// relationGeometry joins the member ways of a multipolygon (outer role) or
// any other relation (e.g. a school mapped as type=site) into closed rings.
// Holes are dropped: the zone reaches 100 m out from the outline anyway.
func relationGeometry(el osmElement) (Geometry, bool) {
	var lines [][]pt
	var nodes []pt
	multipolygon := el.Tags["type"] == "multipolygon" || el.Tags["type"] == "boundary"
	for _, m := range el.Members {
		switch m.Type {
		case "way":
			if multipolygon && m.Role != "outer" && m.Role != "" {
				continue
			}
			if l := points(m.Geometry); len(l) >= 2 {
				lines = append(lines, l)
			}
		case "node":
			if m.Lat != nil && m.Lon != nil {
				nodes = append(nodes, pt{*m.Lat, *m.Lon})
			}
		}
	}
	var polys [][][]pt
	for _, ring := range joinRings(lines) {
		polys = append(polys, [][]pt{roundAll(simplify(ring, simplifyTolerance))})
	}
	switch {
	case len(polys) == 1:
		return encode("Polygon", polys[0])
	case len(polys) > 1:
		return encode("MultiPolygon", polys)
	case len(nodes) > 0:
		return encode("Point", round(nodes[0]))
	}
	return Geometry{}, false
}

// joinRings chains ways that share end points into closed rings. Chains
// that do not close (members outside the data Overpass returned) are closed
// straight when they span an area (3+ points); the rest are dropped.
func joinRings(lines [][]pt) [][]pt {
	var rings [][]pt
	used := make([]bool, len(lines))
	for i := range lines {
		if used[i] {
			continue
		}
		used[i] = true
		ring := append([]pt(nil), lines[i]...)
		for !closed(ring) {
			grown := false
			for j := range lines {
				if used[j] {
					continue
				}
				l := lines[j]
				end := ring[len(ring)-1]
				switch {
				case l[0] == end:
					ring = append(ring, l[1:]...)
				case l[len(l)-1] == end:
					for k := len(l) - 2; k >= 0; k-- {
						ring = append(ring, l[k])
					}
				default:
					continue
				}
				used[j], grown = true, true
				break
			}
			if !grown {
				break
			}
		}
		if !closed(ring) {
			if len(ring) < 3 {
				continue
			}
			ring = append(ring, ring[0])
		}
		rings = append(rings, ring)
	}
	return rings
}

func encode(typ string, coords any) (Geometry, bool) {
	raw, err := json.Marshal(coords)
	if err != nil {
		return Geometry{}, false
	}
	return Geometry{Type: typ, Coordinates: raw}, true
}

// round keeps 6 decimals (about 0.1 m), which keeps the JSON short.
func round(p pt) pt {
	return pt{math.Round(p[0]*1e6) / 1e6, math.Round(p[1]*1e6) / 1e6}
}

func roundAll(line []pt) []pt {
	out := make([]pt, len(line))
	for i, p := range line {
		out[i] = round(p)
	}
	return out
}
