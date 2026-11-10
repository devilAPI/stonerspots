package zones

import (
	"context"
	"database/sql"
	"log"
	"math"
	"sort"
	"time"
)

// (variables: tests shorten them)
var (
	// prefetchPause is the gap between two prefetched blocks: one query at
	// a time, slowly (a pass over Germany is a few thousand queries, spread
	// over days, well inside what public Overpass servers allow).
	prefetchPause = 20 * time.Second
	// prefetchBackoff follows a block that could not be fetched.
	prefetchBackoff = 2 * time.Minute
	// prefetchIdle is the wait after a pass before the next one starts; it
	// skips every block that is still fresh.
	prefetchIdle = 6 * time.Hour
)

// Germany's bounding box, a little wider (the grid of blocks to visit).
const (
	germanyS, germanyN = 47.2, 55.1
	germanyW, germanyE = 5.8, 15.1
)

// germanBlocks are the blocks with some part in Germany, row by row.
func germanBlocks() []block {
	size := TileSize * BlockTiles
	y0, y1 := int(math.Floor(germanyS/size)), int(math.Floor(germanyN/size))
	x0, x1 := int(math.Floor(germanyW/size)), int(math.Floor(germanyE/size))
	var out []block
	for y := y0; y <= y1; y++ {
		for x := x0; x <= x1; x++ {
			b := block{Y: y, X: x}
			if GermanyOverlap(b.Bounds()) != Outside {
				out = append(out, b)
			}
		}
	}
	return out
}

// prefetchOrder puts the blocks with the most spots first (where people
// look), then the rest of Germany.
func prefetchOrder(spots [][2]float64) []block {
	count := map[block]int{}
	for _, p := range spots {
		count[blockOf(tileAt(p[0], p[1]))]++
	}
	all := germanBlocks()
	sort.SliceStable(all, func(i, j int) bool { return count[all[i]] > count[all[j]] })
	return all
}

// spotLocations reads lat/lon of the active spots.
func spotLocations(ctx context.Context, db *sql.DB) ([][2]float64, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT ST_Y(location), ST_X(location) FROM spots WHERE status = 'active'`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out [][2]float64
	for rows.Next() {
		var p [2]float64
		if err := rows.Scan(&p[0], &p[1]); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// stale tells whether b needs fetching: one of its German tiles is missing
// from the store or older than cacheTTL.
func (s *Service) staleBlock(ctx context.Context, b block) bool {
	for _, t := range b.Tiles() {
		if GermanyOverlap(t.Bounds()) == Outside {
			continue
		}
		at, ok, err := s.store.fetchedAt(ctx, t.Key())
		if err != nil || !ok || !s.fresh(at) {
			return true
		}
	}
	return false
}

// Prefetch keeps Germany's zones cached: it walks the blocks (those with
// spots first) and fetches each that is missing or due, one at a time,
// pausing between them; then waits and starts over. It runs until ctx
// ends. Map requests share the upstream slots and are never held up by
// more than this one query.
func (s *Service) Prefetch(ctx context.Context, order func(context.Context) []block) {
	sleep := func(d time.Duration) bool {
		t := time.NewTimer(d)
		defer t.Stop()
		select {
		case <-t.C:
			return true
		case <-ctx.Done():
			return false
		}
	}
	for {
		fetched, failed := 0, 0
		for _, b := range order(ctx) {
			if ctx.Err() != nil {
				return
			}
			if !s.staleBlock(ctx, b) {
				continue
			}
			c, err := s.start(b)
			if err == nil {
				select {
				case <-c.done:
					err = c.err
				case <-ctx.Done():
					return
				}
			}
			pause := prefetchPause
			if err != nil {
				failed++
				pause = prefetchBackoff
			} else {
				fetched++
			}
			if !sleep(pause) {
				return
			}
		}
		if fetched > 0 || failed > 0 {
			log.Printf("zones: prefetch pass done: %d blocks fetched, %d failed", fetched, failed)
		}
		if !sleep(prefetchIdle) {
			return
		}
	}
}
