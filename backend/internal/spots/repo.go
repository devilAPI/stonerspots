package spots

import (
	"cmp"
	"context"
	"database/sql"
	"fmt"
	"math"
	"slices"
	"strconv"
	"strings"

	"stonerspots/backend/internal/app"
	"stonerspots/backend/internal/spots/tagset"
)

// Repo accesses the spots table.
type Repo struct {
	DB            *sql.DB
	PublicBaseURL string
}

const selectCols = `s.id, s.title, s.description, ST_Y(s.location), ST_X(s.location),
  s.like_count, s.created_at,
  COALESCE((SELECT CONCAT(?, '/api/v1/media/', p.` + "`key`" + `)
            FROM photos p JOIN spot_updates u ON u.id = p.update_id
            WHERE u.spot_id = s.id AND u.status = 'active' AND p.status = 'approved'
            ORDER BY p.id LIMIT 1), ''),
  (SELECT COALESCE(ROUND(AVG(rv.rating), 1), 0) FROM spot_reviews rv WHERE rv.spot_id = s.id AND rv.status = 'active'),
  (SELECT COUNT(*) FROM spot_reviews rv WHERE rv.spot_id = s.id AND rv.status = 'active'),
  u.id, u.display_name, u.avatar_key`

// fromSpots is the FROM clause for selectCols: the author comes from one
// primary-key join; a LEFT JOIN, so a spot whose account is gone still lists
// (with author null).
const fromSpots = ` FROM spots s LEFT JOIN users u ON u.id = s.user_id`

func f(v float64) string { return strconv.FormatFloat(v, 'f', -1, 64) }

func polygon(b BBox) string {
	return fmt.Sprintf("POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))",
		f(b.West), f(b.South), f(b.East), f(b.South), f(b.East), f(b.North), f(b.West), f(b.North), f(b.West), f(b.South))
}

// Create inserts a spot with its (normalized) tags in one transaction and returns its id.
func (r *Repo) Create(ctx context.Context, s Spot, userID uint64) (uint64, error) {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback() //nolint:errcheck
	res, err := tx.ExecContext(ctx,
		`INSERT INTO spots (user_id, title, description, location) VALUES (?, ?, ?, POINT(?, ?))`,
		userID, s.Title, s.Description, s.Lon, s.Lat)
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	if err := tagset.Replace(ctx, tx, uint64(id), s.Tags); err != nil {
		return 0, err
	}
	return uint64(id), tx.Commit()
}

// SetTags replaces the tag set of a spot atomically.
func (r *Repo) SetTags(ctx context.Context, id uint64, tags []string) error {
	tx, err := r.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck
	if err := tagset.Replace(ctx, tx, id, tags); err != nil {
		return err
	}
	return tx.Commit()
}

// OwnerAndLock returns the author of an active spot and whether it is
// locked, or sql.ErrNoRows.
func (r *Repo) OwnerAndLock(ctx context.Context, id uint64) (owner uint64, locked bool, err error) {
	err = r.DB.QueryRowContext(ctx, `SELECT user_id, locked FROM spots WHERE id = ? AND status = 'active'`, id).Scan(&owner, &locked)
	return owner, locked, err
}

// attachTags loads the tags of all spots with a single query; spots without tags get [].
func (r *Repo) attachTags(ctx context.Context, list []Spot) error {
	ids := make([]uint64, len(list))
	for i, s := range list {
		ids[i] = s.ID
	}
	m, err := tagset.Load(ctx, r.DB, ids)
	if err != nil {
		return err
	}
	for i := range list {
		list[i].Tags = m[list[i].ID]
		if list[i].Tags == nil {
			list[i].Tags = []string{}
		}
	}
	return nil
}

// Get returns an active spot, or sql.ErrNoRows.
func (r *Repo) Get(ctx context.Context, id uint64) (*Spot, error) {
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+fromSpots+` WHERE s.id = ? AND s.status = 'active'`, r.PublicBaseURL, id)
	if err != nil {
		return nil, err
	}
	list, err := r.scan(rows, false)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, sql.ErrNoRows
	}
	if err := r.attachTags(ctx, list); err != nil {
		return nil, err
	}
	var comments int
	if err := r.DB.QueryRowContext(ctx,
		`SELECT locked, (SELECT COUNT(*) FROM comments c WHERE c.spot_id = s.id AND c.status = 'active')
		FROM spots s WHERE s.id = ?`, id).Scan(&list[0].Locked, &comments); err != nil {
		return nil, err
	}
	list[0].CommentCount = &comments
	return &list[0], nil
}

// ByIDs returns the active spots among ids, in the order of ids.
func (r *Repo) ByIDs(ctx context.Context, ids []uint64) ([]Spot, error) {
	if len(ids) == 0 {
		return []Spot{}, nil
	}
	args := make([]any, 0, len(ids)+1)
	args = append(args, r.PublicBaseURL)
	for _, id := range ids {
		args = append(args, id)
	}
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+fromSpots+` WHERE s.status = 'active' AND s.id IN (?`+strings.Repeat(",?", len(ids)-1)+`)`, args...)
	if err != nil {
		return nil, err
	}
	found, err := r.scan(rows, false)
	if err != nil {
		return nil, err
	}
	if err := r.attachTags(ctx, found); err != nil {
		return nil, err
	}
	byID := make(map[uint64]Spot, len(found))
	for _, s := range found {
		byID[s.ID] = s
	}
	out := make([]Spot, 0, len(found))
	for _, id := range ids {
		if s, ok := byID[id]; ok {
			out = append(out, s)
		}
	}
	return out, nil
}

// bboxQuery builds the query for the spots inside a box: only id, position
// and likes, at most maxPins, unsorted (InBBox sorts). MariaDB estimates a
// spatial range as the whole table and then prefers a full scan for any
// large LIMIT, hence FORCE INDEX on the spatial index.
func bboxQuery(b BBox, fl Filter) (string, []any) {
	q := `SELECT s.id, ST_X(s.location), ST_Y(s.location), s.like_count
	 FROM spots s FORCE INDEX (idx_spots_location)
	 WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)`
	args := []any{polygon(b)}
	tq, targs := tagset.FilterSQL("s", fl.Tags)
	q += tq
	args = append(args, targs...)
	q += ` LIMIT ?`
	args = append(args, maxPins)
	return q, args
}

func clampLimit(n int) int { return clampTo(n, maxLimit) }

func clampTo(n, max int) int {
	if n <= 0 {
		return defaultLimit
	}
	return min(n, max)
}

// pin is a spot's id and position, for choosing which spots of a box to send.
type pin struct {
	id       uint64
	lon, lat float64
	likes    int
}

// InBBox returns active spots inside b, best first. Always non-nil.
//
// When the box holds more spots than the limit (a zoomed-out map), they are
// spread over it: the box is cut into a grid and every cell gets its best
// spots in turn. Otherwise the best-liked spots of a dense area would push
// out every other area (a city's popular spots hid whole regions of newer
// ones).
func (r *Repo) InBBox(ctx context.Context, b BBox, fl Filter) ([]Spot, error) {
	if b.South == b.North || b.West == b.East {
		return []Spot{}, nil // zero-area box cannot contain a polygon
	}
	q, args := bboxQuery(b, fl)
	rows, err := r.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	var pins []pin
	for rows.Next() {
		var p pin
		if err := rows.Scan(&p.id, &p.lon, &p.lat, &p.likes); err != nil {
			rows.Close()
			return nil, err
		}
		pins = append(pins, p)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	// best first: most liked, then oldest
	slices.SortFunc(pins, func(a, b pin) int {
		if a.likes != b.likes {
			return b.likes - a.likes
		}
		return cmp.Compare(a.id, b.id)
	})
	return r.ByIDs(ctx, spread(pins, b, clampTo(fl.Limit, maxBBoxLimit)))
}

// spread picks limit of pins (best first) so that they cover the box b:
// round by round, each grid cell that still has spots gives its next best.
// The result keeps the order of pins.
func spread(pins []pin, b BBox, limit int) []uint64 {
	if len(pins) <= limit {
		ids := make([]uint64, len(pins))
		for i, p := range pins {
			ids[i] = p.id
		}
		return ids
	}
	g := int(math.Ceil(math.Sqrt(float64(limit))))
	cell := func(v, lo, hi float64) int {
		c := int((v - lo) / (hi - lo) * float64(g))
		return max(0, min(g-1, c))
	}
	// cells in the order of their best spot, each with its spots best first
	var cells [][]int
	index := map[int]int{}
	for i, p := range pins {
		k := cell(p.lat, b.South, b.North)*g + cell(p.lon, b.West, b.East)
		n, ok := index[k]
		if !ok {
			n = len(cells)
			index[k] = n
			cells = append(cells, nil)
		}
		cells[n] = append(cells[n], i)
	}
	take := make([]bool, len(pins))
	for round, n := 0, 0; n < limit; round++ {
		for _, c := range cells {
			if round < len(c) && n < limit {
				take[c[round]] = true
				n++
			}
		}
	}
	ids := make([]uint64, 0, limit)
	for i, p := range pins {
		if take[i] {
			ids = append(ids, p.id)
		}
	}
	return ids
}

// Nearby returns active spots within radiusM metres, nearest first. Always non-nil.
func (r *Repo) Nearby(ctx context.Context, lat, lon float64, radiusM, limit int, tags []string) ([]Spot, error) {
	// Prefilter with a slightly generous box so the spatial index applies.
	dLat := float64(radiusM)/111000.0 + 1e-4
	cos := math.Max(math.Cos(lat*math.Pi/180), 0.01)
	dLon := float64(radiusM)/(111000.0*cos) + 1e-4
	box := BBox{South: lat - dLat, North: lat + dLat, West: lon - dLon, East: lon + dLon}
	tq, targs := tagset.FilterSQL("s", tags)
	args := append([]any{r.PublicBaseURL, lon, lat, polygon(box)}, targs...)
	args = append(args, radiusM, clampLimit(limit))
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+`, ST_Distance_Sphere(s.location, POINT(?, ?)) AS dist
		`+fromSpots+`
		 WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)`+tq+`
		 HAVING dist <= ?
		 ORDER BY dist ASC, s.id ASC LIMIT ?`, args...)
	if err != nil {
		return nil, err
	}
	list, err := r.scan(rows, true)
	if err != nil {
		return nil, err
	}
	return list, r.attachTags(ctx, list)
}

// FindWithin returns the nearest active spot within meters, or nil.
func (r *Repo) FindWithin(ctx context.Context, lat, lon, meters float64) (*Spot, error) {
	list, err := r.nearestWithin(ctx, lat, lon, meters)
	if err != nil || len(list) == 0 {
		return nil, err
	}
	return &list[0], nil
}

func (r *Repo) nearestWithin(ctx context.Context, lat, lon, meters float64) ([]Spot, error) {
	dLat := meters/111000.0 + 1e-4
	cos := math.Max(math.Cos(lat*math.Pi/180), 0.01)
	dLon := meters/(111000.0*cos) + 1e-4
	box := BBox{South: lat - dLat, North: lat + dLat, West: lon - dLon, East: lon + dLon}
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+`, ST_Distance_Sphere(s.location, POINT(?, ?)) AS dist
		`+fromSpots+`
		 WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)
		 HAVING dist <= ?
		 ORDER BY dist ASC, s.id ASC LIMIT 1`,
		r.PublicBaseURL, lon, lat, polygon(box), meters)
	if err != nil {
		return nil, err
	}
	return r.scan(rows, true)
}

func (r *Repo) scan(rows *sql.Rows, withDist bool) ([]Spot, error) {
	defer rows.Close()
	out := []Spot{}
	for rows.Next() {
		s := Spot{Tags: []string{}}
		var (
			authorID   sql.NullInt64
			authorName sql.NullString
			avatarKey  sql.NullString
		)
		dst := []any{&s.ID, &s.Title, &s.Description, &s.Lat, &s.Lon, &s.LikeCount, &s.CreatedAt, &s.CoverURL, &s.RatingAvg, &s.RatingCount,
			&authorID, &authorName, &avatarKey}
		var d float64
		if withDist {
			dst = append(dst, &d)
		}
		if err := rows.Scan(dst...); err != nil {
			return nil, err
		}
		if withDist {
			d = math.Round(d*10) / 10
			s.DistanceM = &d
		}
		if authorID.Valid {
			s.Author = &Author{ID: uint64(authorID.Int64), DisplayName: authorName.String,
				AvatarURL: app.AvatarURL(r.PublicBaseURL, avatarKey)}
		}
		out = append(out, s)
	}
	return out, rows.Err()
}
