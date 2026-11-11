package spots

import (
	"context"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"
	"unicode/utf8"

	"stonerspots/backend/internal/httpx"
	"stonerspots/backend/internal/textmatch"
)

// Search limits: query length in characters and number of results.
const (
	SearchMinLen, SearchMaxLen = 2, 80
	searchLimit                = 20
)

// candidate is an active spot as the search ranks it.
type candidate struct {
	id      uint64
	tier    int
	score   float64
	dist    float64 // metres; 0 without a position
	rating  float64
	created time.Time
}

// Search returns at most searchLimit active spots whose title (or, weaker,
// description) matches q, see textmatch. Better tiers come first; within
// a tier, with a position (near != nil) the nearest first (they then carry
// distance_m), otherwise the best match, then rating and newest. Always
// non-nil. The match runs here, not in SQL: it reads the titles of all
// active spots, which are few (thousands at most).
func (r *Repo) Search(ctx context.Context, q string, near *[2]float64) ([]Spot, error) {
	query := textmatch.NewQuery(q)
	if query.Empty() {
		return []Spot{}, nil
	}
	rows, err := r.DB.QueryContext(ctx, `SELECT s.id, s.title, LEFT(s.description, 1000),
		ST_Y(s.location), ST_X(s.location), COALESCE(rv.avg, 0), s.created_at
		FROM spots s
		LEFT JOIN (SELECT spot_id, AVG(rating) AS avg FROM spot_reviews
		  WHERE status = 'active' GROUP BY spot_id) rv ON rv.spot_id = s.id
		WHERE s.status = 'active'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var found []candidate
	for rows.Next() {
		var (
			c           candidate
			title, desc string
			lat, lon    float64
		)
		if err := rows.Scan(&c.id, &title, &desc, &lat, &lon, &c.rating, &c.created); err != nil {
			return nil, err
		}
		tier, score, ok := query.Match(title, desc)
		if !ok {
			continue
		}
		c.tier, c.score = tier, score
		if near != nil {
			c.dist = distanceM(near[0], near[1], lat, lon)
		}
		found = append(found, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	sort.Slice(found, func(i, j int) bool {
		a, b := found[i], found[j]
		if a.tier != b.tier {
			return a.tier < b.tier
		}
		if near != nil && a.dist != b.dist {
			return a.dist < b.dist
		}
		if a.score != b.score {
			return a.score > b.score
		}
		if a.rating != b.rating {
			return a.rating > b.rating
		}
		if !a.created.Equal(b.created) {
			return a.created.After(b.created)
		}
		return a.id > b.id
	})
	if len(found) > searchLimit {
		found = found[:searchLimit]
	}
	if len(found) == 0 {
		return []Spot{}, nil
	}
	return r.byIDs(ctx, found, near)
}

// byIDs loads the spots of found, in that order.
func (r *Repo) byIDs(ctx context.Context, found []candidate, near *[2]float64) ([]Spot, error) {
	ids := make([]any, len(found))
	for i, c := range found {
		ids[i] = c.id
	}
	in := "?" + strings.Repeat(", ?", len(ids)-1)
	var (
		query string
		args  []any
	)
	if near != nil {
		query = `SELECT ` + selectCols + `, ST_Distance_Sphere(s.location, POINT(?, ?)) AS dist` +
			fromSpots + ` WHERE s.id IN (` + in + `)`
		args = append([]any{r.PublicBaseURL, near[1], near[0]}, ids...)
	} else {
		query = `SELECT ` + selectCols + fromSpots + ` WHERE s.id IN (` + in + `)`
		args = append([]any{r.PublicBaseURL}, ids...)
	}
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	list, err := r.scan(rows, near != nil)
	if err != nil {
		return nil, err
	}
	pos := make(map[uint64]int, len(found))
	for i, c := range found {
		pos[c.id] = i
	}
	sort.Slice(list, func(i, j int) bool { return pos[list[i].ID] < pos[list[j].ID] })
	return list, r.attachTags(ctx, list)
}

// distanceM is the great-circle distance in metres, on the sphere MariaDB's
// ST_Distance_Sphere uses.
func distanceM(lat1, lon1, lat2, lon2 float64) float64 {
	const earth = 6370986 // metres
	rad := math.Pi / 180
	dLat, dLon := (lat2-lat1)*rad, (lon2-lon1)*rad
	h := math.Sin(dLat/2)*math.Sin(dLat/2) +
		math.Cos(lat1*rad)*math.Cos(lat2*rad)*math.Sin(dLon/2)*math.Sin(dLon/2)
	return 2 * earth * math.Asin(math.Min(1, math.Sqrt(h)))
}

// search answers GET /spots/search?q=&lat=&lon=.
func (h *handler) search(w http.ResponseWriter, r *http.Request) {
	q := strings.Join(strings.Fields(r.URL.Query().Get("q")), " ")
	if n := utf8.RuneCountInString(q); n < SearchMinLen || n > SearchMaxLen {
		httpx.Error(w, http.StatusBadRequest, "invalid_query", "q must be 2-80 characters")
		return
	}
	var near *[2]float64
	qs := r.URL.Query()
	if qs.Has("lat") || qs.Has("lon") {
		lat, ok1 := floatParam(r, "lat")
		lon, ok2 := floatParam(r, "lon")
		if !ok1 || !ok2 || !validCoord(lat, lon) {
			httpx.Error(w, http.StatusBadRequest, "invalid_location", "lat must be in -90..90 and lon in -180..180, and both must be given")
			return
		}
		near = &[2]float64{lat, lon}
	}
	list, err := h.repo.Search(r.Context(), q, near)
	if err != nil {
		internal(w, err)
		return
	}
	httpx.JSON(w, http.StatusOK, list)
}
