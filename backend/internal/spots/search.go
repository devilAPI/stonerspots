package spots

import (
	"context"
	"net/http"
	"strings"
	"unicode/utf8"

	"stonerspots/backend/internal/httpx"
)

// Search limits: query length in characters and number of results.
const (
	SearchMinLen, SearchMaxLen = 2, 80
	searchLimit                = 20
)

// LikeEscape escapes the LIKE wildcards (and the escape character itself)
// so user input only ever matches literally.
func LikeEscape(s string) string {
	return strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`).Replace(s)
}

// matchRank orders name matches: exact title, title prefix, word prefix,
// anything else. The column collation (utf8mb4_unicode_ci) makes every
// comparison case- and accent-insensitive.
const matchRank = `CASE WHEN s.title = ? THEN 0 WHEN s.title LIKE ? THEN 1 WHEN s.title LIKE ? THEN 2 ELSE 3 END`

// Search returns at most searchLimit active spots whose title contains q.
// With a position (near != nil) they come nearest first and carry
// distance_m; otherwise best match first, then rating and newest. Always
// non-nil. A substring match cannot use a B-tree index, so this scans the
// active spots; the table is small (one region) and the scan is cheap.
func (r *Repo) Search(ctx context.Context, q string, near *[2]float64) ([]Spot, error) {
	esc := LikeEscape(q)
	rankArgs := []any{q, esc + "%", "% " + esc + "%"}
	var (
		query string
		args  []any
	)
	if near != nil {
		lat, lon := near[0], near[1]
		query = `SELECT ` + selectCols + `, ST_Distance_Sphere(s.location, POINT(?, ?)) AS dist
		` + fromSpots + `
		 WHERE s.status = 'active' AND s.title LIKE ?
		 ORDER BY dist ASC, ` + matchRank + `, s.id DESC LIMIT ?`
		args = append([]any{r.PublicBaseURL, lon, lat, "%" + esc + "%"}, rankArgs...)
	} else {
		query = `SELECT ` + selectCols + `
		` + fromSpots + `
		 WHERE s.status = 'active' AND s.title LIKE ?
		 ORDER BY ` + matchRank + `,
		   (SELECT COALESCE(AVG(rv.rating), 0) FROM spot_reviews rv WHERE rv.spot_id = s.id AND rv.status = 'active') DESC,
		   s.created_at DESC, s.id DESC LIMIT ?`
		args = append([]any{r.PublicBaseURL, "%" + esc + "%"}, rankArgs...)
	}
	args = append(args, searchLimit)
	rows, err := r.DB.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	list, err := r.scan(rows, near != nil)
	if err != nil {
		return nil, err
	}
	return list, r.attachTags(ctx, list)
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
