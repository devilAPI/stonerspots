// Command seedgpx imports the waypoints of a GPX file as spots through the
// public API. It is meant for local demo data and is safe to re-run: points
// that already exist (same title within 2 m) are skipped.
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

func (c *client) exists(lat, lon float64, title string) bool {
	q := url.Values{"lat": {fmt.Sprint(lat)}, "lon": {fmt.Sprint(lon)}, "radius_m": {"2"}, "limit": {"50"}}
	code, b, err := c.do("GET", "/spots/nearby?"+q.Encode(), nil)
	if err != nil || code != 200 {
		return false
	}
	var spots []struct {
		Title string `json:"title"`
	}
	_ = json.Unmarshal(b, &spots)
	for _, s := range spots {
		if s.Title == title {
			return true
		}
	}
	return false
}

func main() {
	file := flag.String("gpx", "", "path to the GPX file (required)")
	api := flag.String("api", "http://localhost:8080/api/v1", "API base URL")
	email := flag.String("email", "demo@example.com", "account to create the spots with (registered if missing)")
	password := flag.String("password", "correct-horse-1", "account password")
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

	created, skipped, failed := 0, 0, 0
	cats := map[string]int{}
	for _, w := range doc.Waypoints {
		t := title(w.Name, w.Desc)
		cat := category(w.Name + " " + w.Desc)
		if *dry {
			fmt.Printf("%-10s %.5f,%.5f  %s\n", cat, w.Lat, w.Lon, t)
			created++
			cats[cat]++
			continue
		}
		if c.exists(w.Lat, w.Lon, t) {
			skipped++
			continue
		}
		// force: demo data legitimately has several spots a few metres apart.
		code, b, err := c.do("POST", "/spots", map[string]any{
			"title": t, "description": truncate(strings.TrimSpace(w.Desc), 1000), "category": cat,
			"lat": w.Lat, "lon": w.Lon, "force": true,
		})
		if err != nil || code != http.StatusCreated {
			failed++
			log.Printf("FAIL %q: %d %s %v", t, code, b, err)
			continue
		}
		created++
		cats[cat]++
	}
	fmt.Printf("created=%d skipped=%d failed=%d categories=%v\n", created, skipped, failed, cats)
	if failed > 0 {
		os.Exit(1)
	}
}
