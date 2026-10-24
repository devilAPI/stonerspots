// Package spots implements spots: create, get, map bounding-box query and nearby search.
package spots

import "time"

// Spot is a place on the map. Coordinates are degrees (lat, lon).
type Spot struct {
	ID          uint64    `json:"id"`
	Title       string    `json:"title"`
	Description string    `json:"description"`
	Category    string    `json:"category"`
	Lat         float64   `json:"lat"`
	Lon         float64   `json:"lon"`
	LikeCount   int       `json:"like_count"`
	CoverURL    string    `json:"cover_url"`
	RatingAvg   float64   `json:"rating_avg"`
	RatingCount int       `json:"rating_count"`
	DistanceM   *float64  `json:"distance_m,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

// BBox is a geographic bounding box in degrees.
type BBox struct{ South, West, North, East float64 }

// Filter narrows a bounding-box query.
type Filter struct {
	Category string // empty = all
	Limit    int
}

// Categories lists the allowed spot categories.
var Categories = map[string]bool{
	"bench": true, "river": true, "lake": true, "viewpoint": true,
	"forest": true, "park": true, "other": true,
}

// Region bounding box (DACH, rough) and duplicate radius.
const (
	regionSouth, regionNorth = 45.8, 55.1
	regionWest, regionEast   = 5.8, 17.2
	duplicateMeters          = 25.0
	maxNearbyRadius          = 50000
	defaultLimit, maxLimit   = 20, 200
)
