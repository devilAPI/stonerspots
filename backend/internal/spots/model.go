// Package spots implements spots: create, get, map bounding-box query and nearby search.
package spots

import (
	"context"
	"time"

	"stonerspots/backend/internal/spots/tagset"
)

// Spot is a place on the map. Coordinates are degrees (lat, lon).
type Spot struct {
	ID          uint64   `json:"id"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	Lat         float64  `json:"lat"`
	Lon         float64  `json:"lon"`
	LikeCount   int      `json:"like_count"`
	CoverURL    string   `json:"cover_url"`
	RatingAvg   float64  `json:"rating_avg"`
	RatingCount int      `json:"rating_count"`
	Tags        []string `json:"tags"`
	Author      *Author  `json:"author,omitempty"` // only on GET /spots/{id}
	// Locked spots take no new updates or edits from non-admins. Only set on
	// GET /spots/{id}.
	Locked    bool      `json:"locked"`
	DistanceM *float64  `json:"distance_m,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

// Author is the user who created a spot.
type Author struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

// NormalizeTags validates against the tag catalog, dedupes and orders tags
// canonically.
func NormalizeTags(ctx context.Context, q tagset.Querier, in []string) ([]string, error) {
	return tagset.Normalize(ctx, q, in)
}

// BBox is a geographic bounding box in degrees.
type BBox struct{ South, West, North, East float64 }

// Filter narrows a bounding-box query.
type Filter struct {
	Tags  []string // normalized; spots must have ALL of them
	Limit int
}

// Region bounding box (DACH, rough) and duplicate radius.
const (
	regionSouth, regionNorth = 45.8, 55.1
	regionWest, regionEast   = 5.8, 17.2
	duplicateMeters          = 25.0
	maxNearbyRadius          = 50000
	defaultLimit, maxLimit   = 20, 200
)
