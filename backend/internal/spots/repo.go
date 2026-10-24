package spots

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"strconv"
)

// Repo accesses the spots table.
type Repo struct {
	DB            *sql.DB
	PublicBaseURL string
}

const selectCols = `s.id, s.title, s.description, s.category, ST_Y(s.location), ST_X(s.location),
  s.like_count, s.created_at,
  COALESCE((SELECT CONCAT(?, '/api/v1/media/', p.` + "`key`" + `)
            FROM photos p JOIN spot_updates u ON u.id = p.update_id
            WHERE u.spot_id = s.id AND u.status = 'active'
            ORDER BY p.id LIMIT 1), '')`

func f(v float64) string { return strconv.FormatFloat(v, 'f', -1, 64) }

func polygon(b BBox) string {
	return fmt.Sprintf("POLYGON((%s %s,%s %s,%s %s,%s %s,%s %s))",
		f(b.West), f(b.South), f(b.East), f(b.South), f(b.East), f(b.North), f(b.West), f(b.North), f(b.West), f(b.South))
}

// Create inserts a spot and returns its id.
func (r *Repo) Create(ctx context.Context, s Spot, userID uint64) (uint64, error) {
	res, err := r.DB.ExecContext(ctx,
		`INSERT INTO spots (user_id, title, description, category, location) VALUES (?, ?, ?, ?, POINT(?, ?))`,
		userID, s.Title, s.Description, s.Category, s.Lon, s.Lat)
	if err != nil {
		return 0, err
	}
	id, err := res.LastInsertId()
	return uint64(id), err
}

// Get returns an active spot, or sql.ErrNoRows.
func (r *Repo) Get(ctx context.Context, id uint64) (*Spot, error) {
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+` FROM spots s WHERE s.id = ? AND s.status = 'active'`, r.PublicBaseURL, id)
	if err != nil {
		return nil, err
	}
	list, err := scan(rows, false)
	if err != nil {
		return nil, err
	}
	if len(list) == 0 {
		return nil, sql.ErrNoRows
	}
	return &list[0], nil
}

// bboxQuery builds the bounding-box query. MBRContains lets MariaDB use the spatial index.
func bboxQuery(b BBox, fl Filter) (string, []any) {
	q := `SELECT ` + selectCols + ` FROM spots s WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)`
	args := []any{"", polygon(b)}
	if fl.Category != "" {
		q += ` AND s.category = ?`
		args = append(args, fl.Category)
	}
	q += ` ORDER BY s.like_count DESC, s.id ASC LIMIT ?`
	args = append(args, clampLimit(fl.Limit))
	return q, args
}

func clampLimit(n int) int {
	if n <= 0 {
		return defaultLimit
	}
	if n > maxLimit {
		return maxLimit
	}
	return n
}

// InBBox returns active spots inside b, best first. Always non-nil.
func (r *Repo) InBBox(ctx context.Context, b BBox, fl Filter) ([]Spot, error) {
	if b.South == b.North || b.West == b.East {
		return []Spot{}, nil // zero-area box cannot contain a polygon
	}
	q, args := bboxQuery(b, fl)
	args[0] = r.PublicBaseURL
	rows, err := r.DB.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	return scan(rows, false)
}

// Nearby returns active spots within radiusM metres, nearest first. Always non-nil.
func (r *Repo) Nearby(ctx context.Context, lat, lon float64, radiusM, limit int) ([]Spot, error) {
	// Prefilter with a slightly generous box so the spatial index applies.
	dLat := float64(radiusM)/111000.0 + 1e-4
	cos := math.Max(math.Cos(lat*math.Pi/180), 0.01)
	dLon := float64(radiusM)/(111000.0*cos) + 1e-4
	box := BBox{South: lat - dLat, North: lat + dLat, West: lon - dLon, East: lon + dLon}
	rows, err := r.DB.QueryContext(ctx,
		`SELECT `+selectCols+`, ST_Distance_Sphere(s.location, POINT(?, ?)) AS dist
		 FROM spots s
		 WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)
		 HAVING dist <= ?
		 ORDER BY dist ASC, s.id ASC LIMIT ?`,
		r.PublicBaseURL, lon, lat, polygon(box), radiusM, clampLimit(limit))
	if err != nil {
		return nil, err
	}
	return scan(rows, true)
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
		 FROM spots s
		 WHERE s.status = 'active' AND MBRContains(ST_GeomFromText(?), s.location)
		 HAVING dist <= ?
		 ORDER BY dist ASC, s.id ASC LIMIT 1`,
		r.PublicBaseURL, lon, lat, polygon(box), meters)
	if err != nil {
		return nil, err
	}
	return scan(rows, true)
}

func scan(rows *sql.Rows, withDist bool) ([]Spot, error) {
	defer rows.Close()
	out := []Spot{}
	for rows.Next() {
		var s Spot
		dst := []any{&s.ID, &s.Title, &s.Description, &s.Category, &s.Lat, &s.Lon, &s.LikeCount, &s.CreatedAt, &s.CoverURL}
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
		out = append(out, s)
	}
	return out, rows.Err()
}
