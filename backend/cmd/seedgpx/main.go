// Command seedgpx imports the waypoints of a GPX file as spots through the
// public API. It is meant for local demo data and is safe to re-run: points
// that already exist (same title within 2 m) are skipped, or re-tagged with
// -retag. Tags are inferred from the waypoint name and description.
//
//	go run ./cmd/seedgpx -gpx ~/Downloads/Spots.gpx
package main

import (
	"bytes"
	"encoding/json"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"unicode/utf8"
)

type gpx struct {
	Waypoints []struct {
		Lat  float64 `xml:"lat,attr"`
		Lon  float64 `xml:"lon,attr"`
		Name string  `xml:"name"`
		Desc string  `xml:"desc"`
	} `xml:"wpt"`
}

var (
	coordName = regexp.MustCompile(`^\d+°`)
	reViewpt  = regexp.MustCompile(`aussicht`)
	reBench   = regexp.MustCompile(`bank|bänke|baenke|sitz|ruhestege`)
	reRiver   = regexp.MustCompile(`bach|fluss|isar`)
	reLake    = regexp.MustCompile(`teich|weiher|biotop|see\b`)
	reForest  = regexp.MustCompile(`wald`)
	rePark    = regexp.MustCompile(`park|garten|wiese|spielplatz|grün|skatepark`)
)

func category(text string) string {
	t := strings.ToLower(text)
	switch {
	case reViewpt.MatchString(t):
		return "viewpoint"
	case reBench.MatchString(t):
		return "bench"
	case reRiver.MatchString(t):
		return "river"
	case reLake.MatchString(t):
		return "lake"
	case reForest.MatchString(t):
		return "forest"
	case rePark.MatchString(t):
		return "park"
	}
	return "other"
}

// tagRules maps each spot tag to the (lower-case) words that imply it, in
// canonical tag order.
var tagRules = []struct {
	tag string
	re  *regexp.Regexp
}{
	{"roof", regexp.MustCompile(`überdacht|ueberdacht|dach|hütte|huette|häuschen|haeuschen|tunnel|unterführung|unterfuehrung|glashaus|pavi|container`)},
	{"seating", regexp.MustCompile(`bank|bänke|baenke|sitz`)},
	{"view", regexp.MustCompile(`aussicht|blick`)},
	{"quiet", regexp.MustCompile(`ruhig|entspannt|chill`)},
	{"water", regexp.MustCompile(`teich|weiher|bach|see\b|fluss|brunnen`)},
}

// inferTags derives spot tags from a waypoint's name and description. The
// result is in canonical order and never nil.
func inferTags(text string) []string {
	t := strings.ToLower(text)
	out := []string{}
	for _, r := range tagRules {
		if r.re.MatchString(t) {
			out = append(out, r.tag)
		}
	}
	return out
}

func truncate(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	r := []rune(s)[:n]
	out := string(r)
	if i := strings.LastIndex(out, " "); i > 0 {
		out = out[:i]
	}
	return out + "…"
}

// title picks a usable title: the waypoint name unless it is a generic
// placeholder, then the note, then a fallback.
func title(name, desc string) string {
	n := strings.TrimSpace(name)
	generic := n == "" || strings.EqualFold(n, "Gesetzte Markierung") || strings.EqualFold(n, "Dropped pin") || coordName.MatchString(n)
	t := n
	if generic {
		t = "Unbenannter Spot"
		if d := strings.TrimSpace(desc); d != "" {
			t = truncate(d, 60)
		}
	}
	if utf8.RuneCountInString(t) < 3 {
		t += " Spot"
	}
	return truncate(t, 80)
}

type client struct {
	api, token string
}

func (c *client) do(method, path string, body any) (int, []byte, error) {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, c.api+path, rd)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res.StatusCode, b, nil
}

func (c *client) login(email, password, name string) error {
	creds := map[string]any{"email": email, "password": password}
	code, b, err := c.do("POST", "/auth/login", creds)
	if err != nil {
		return err
	}
	if code == http.StatusUnauthorized {
		creds["display_name"], creds["adult"] = name, true
		code, b, err = c.do("POST", "/auth/register", creds)
		if err != nil {
			return err
		}
	}
	if code != 200 && code != 201 {
		return fmt.Errorf("auth failed: %d %s", code, b)
	}
	var s struct {
		AccessToken string `json:"access_token"`
	}
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	c.token = s.AccessToken
	return nil
}

// find returns the id of a spot with the same title within 2 m, or 0.
func (c *client) find(lat, lon float64, title string) uint64 {
	q := url.Values{"lat": {fmt.Sprint(lat)}, "lon": {fmt.Sprint(lon)}, "radius_m": {"2"}, "limit": {"50"}}
	code, b, err := c.do("GET", "/spots/nearby?"+q.Encode(), nil)
	if err != nil || code != 200 {
		return 0
	}
	var spots []struct {
		ID    uint64 `json:"id"`
		Title string `json:"title"`
	}
	_ = json.Unmarshal(b, &spots)
	for _, s := range spots {
		if s.Title == title {
			return s.ID
		}
	}
	return 0
}

func main() {
	file := flag.String("gpx", "", "path to the GPX file (required)")
	api := flag.String("api", "http://localhost:8080/api/v1", "API base URL")
	email := flag.String("email", "demo@example.com", "account to create the spots with (registered if missing)")
	password := flag.String("password", "correct-horse-1", "account password")
	retag := flag.Bool("retag", false, "for waypoints whose spot already exists, replace its tags with the inferred ones (PUT /spots/{id}/tags) instead of skipping")
	dry := flag.Bool("dry-run", false, "print what would be created without calling the API")
	flag.Parse()
	if *file == "" {
		flag.Usage()
		os.Exit(2)
	}

	f, err := os.Open(*file)
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	var doc gpx
	if err := xml.NewDecoder(f).Decode(&doc); err != nil {
		log.Fatalf("parse gpx: %v", err)
	}

	c := &client{api: strings.TrimRight(*api, "/")}
	if !*dry {
		if err := c.login(*email, *password, "Demo"); err != nil {
			log.Fatal(err)
		}
	}

	created, skipped, retagged, failed := 0, 0, 0, 0
	cats := map[string]int{}
	for _, w := range doc.Waypoints {
		t := title(w.Name, w.Desc)
		cat := category(w.Name + " " + w.Desc)
		tags := inferTags(w.Name + " " + w.Desc)
		if *dry {
			fmt.Printf("%-10s %.5f,%.5f  %s %v\n", cat, w.Lat, w.Lon, t, tags)
			created++
			cats[cat]++
			continue
		}
		if id := c.find(w.Lat, w.Lon, t); id != 0 {
			if !*retag {
				skipped++
				continue
			}
			code, b, err := c.do("PUT", fmt.Sprintf("/spots/%d/tags", id), map[string]any{"tags": tags})
			if err != nil || code != http.StatusOK {
				failed++
				log.Printf("FAIL retag %q: %d %s %v", t, code, b, err)
				continue
			}
			retagged++
			continue
		}
		// -retag only touches spots that exist. A spot that is gone was removed or
		// renamed on purpose (e.g. by an admin); never bring it back.
		if *retag {
			skipped++
			continue
		}
		// force: demo data legitimately has several spots a few metres apart.
		code, b, err := c.do("POST", "/spots", map[string]any{
			"title": t, "description": truncate(strings.TrimSpace(w.Desc), 1000), "category": cat,
			"lat": w.Lat, "lon": w.Lon, "force": true, "tags": tags,
		})
		if err != nil || code != http.StatusCreated {
			failed++
			log.Printf("FAIL %q: %d %s %v", t, code, b, err)
			continue
		}
		created++
		cats[cat]++
	}
	fmt.Printf("created=%d skipped=%d retagged=%d failed=%d categories=%v\n", created, skipped, retagged, failed, cats)
	if failed > 0 {
		os.Exit(1)
	}
}
