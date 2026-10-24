// Package spots implements spots: create, get, map bounding-box query and nearby search.
package spots

import (
	"time"

	"stonerspots/backend/internal/spots/tagset"
)

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
	Tags        []string  `json:"tags"`
	Author      *Author   `json:"author,omitempty"` // only on GET /spots/{id}
	DistanceM   *float64  `json:"distance_m,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
}

// Author is the user who created a spot.
type Author struct {
	ID          uint64 `json:"id"`
	DisplayName string `json:"display_name"`
}

// Tags is the canonical spot tag list, in canonical order.
var Tags = tagset.Tags

// ValidTag reports whether t is a known spot tag.
func ValidTag(t string) bool { return tagset.Valid(t) }

// NormalizeTags validates, dedupes and orders tags canonically (max 7 entries).
func NormalizeTags(in []string) ([]string, error) { return tagset.Normalize(in) }

// BBox is a geographic bounding box in degrees.
type BBox struct{ South, West, North, East float64 }

// Filter narrows a bounding-box query.
type Filter struct {
	Category string   // empty = all
	Tags     []string // normalized; spots must have ALL of them
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
