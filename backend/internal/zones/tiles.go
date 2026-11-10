package zones

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/url"
	"strconv"
)

// TileSize is the edge of a cache tile in degrees. The app fetches by the
// same grid (app/lib/features/zones/zone_tiles.dart), so neighbouring
// requests hit the same tiles instead of overlapping boxes.
const TileSize = 0.02

// The largest box one request may ask for (degrees). At street-level zoom a
// phone or a desktop window shows less; anything bigger is refused, so the
// layer cannot be used to pull whole cities from Overpass through us.
const (
	maxLatSpan = 0.05
	maxLonSpan = 0.08
)

// gridEps absorbs float noise when a box edge lies on a tile edge
// (0.02*2406 is 48.120000000000005).
const gridEps = 1e-7

// Tile is one cell of the grid: rows by latitude, columns by longitude.
type Tile struct{ Y, X int }

// tileAt is the tile that contains lat/lon.
func tileAt(lat, lon float64) Tile {
	return Tile{Y: int(math.Floor(lat/TileSize + gridEps)), X: int(math.Floor(lon/TileSize + gridEps))}
}

// queryVersion changes whenever buildQuery or kindOf select other places,
// so tiles cached under the old rules are fetched again instead of being
// served for up to cacheTTL (q2: private playgrounds count).
const queryVersion = "q2"

// Key names the tile in the cache. The grid size and the query version are
// part of it, so changing either never serves tiles made under other rules.
func (t Tile) Key() string { return fmt.Sprintf("g2%s:%d:%d", queryVersion, t.Y, t.X) }

// Bounds returns south, west, north, east.
func (t Tile) Bounds() (s, w, n, e float64) {
	return float64(t.Y) * TileSize, float64(t.X) * TileSize,
		float64(t.Y+1) * TileSize, float64(t.X+1) * TileSize
}

// bbox is a validated request box.
type bbox struct{ S, W, N, E float64 }

var errBBox = errors.New("bad bbox")

// parseBBox reads south, west, north, east from the query and checks them.
func parseBBox(q url.Values) (bbox, error) {
	var v [4]float64
	for i, name := range []string{"south", "west", "north", "east"} {
		f, err := strconv.ParseFloat(q.Get(name), 64)
		if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
			return bbox{}, fmt.Errorf("%w: %s must be a number", errBBox, name)
		}
		v[i] = f
	}
	b := bbox{S: v[0], W: v[1], N: v[2], E: v[3]}
	switch {
	case b.S < -90 || b.N > 90 || b.W < -180 || b.E > 180:
		return bbox{}, fmt.Errorf("%w: out of range", errBBox)
	case b.S >= b.N || b.W >= b.E:
		return bbox{}, fmt.Errorf("%w: south/west must be below north/east", errBBox)
	case b.N-b.S > maxLatSpan+gridEps || b.E-b.W > maxLonSpan+gridEps:
		return bbox{}, fmt.Errorf("%w: box too large (at most %.2f° × %.2f°), zoom in", errBBox, maxLatSpan, maxLonSpan)
	}
	return b, nil
}

// tiles are the grid cells that cover b, row by row.
func (b bbox) tiles() []Tile {
	y0 := int(math.Floor(b.S/TileSize + gridEps))
	x0 := int(math.Floor(b.W/TileSize + gridEps))
	y1 := int(math.Ceil(b.N/TileSize-gridEps)) - 1
	x1 := int(math.Ceil(b.E/TileSize-gridEps)) - 1
	var out []Tile
	for y := y0; y <= max(y0, y1); y++ {
		for x := x0; x <= max(x0, x1); x++ {
			out = append(out, Tile{Y: y, X: x})
		}
	}
	return out
}

// BlockTiles is the edge of a block in tiles: Overpass is asked for a block
// at a time (0.08° × 0.08°, about 9 × 6 km in Germany), and its zones are
// cached per tile.
const BlockTiles = 4

// block is one cell of the coarser grid that tiles are fetched by.
type block struct{ Y, X int }

func floorDiv(a, b int) int {
	q := a / b
	if a%b != 0 && (a < 0) != (b < 0) {
		q--
	}
	return q
}

// blockOf is the block that t is in.
func blockOf(t Tile) block { return block{Y: floorDiv(t.Y, BlockTiles), X: floorDiv(t.X, BlockTiles)} }

// Key names the block for fetches in flight and failed ones.
func (b block) Key() string { return fmt.Sprintf("b%s:%d:%d", queryVersion, b.Y, b.X) }

// Tiles are the BlockTiles × BlockTiles tiles of b.
func (b block) Tiles() []Tile {
	out := make([]Tile, 0, BlockTiles*BlockTiles)
	for y := 0; y < BlockTiles; y++ {
		for x := 0; x < BlockTiles; x++ {
			out = append(out, Tile{Y: b.Y*BlockTiles + y, X: b.X*BlockTiles + x})
		}
	}
	return out
}

// Bounds returns south, west, north, east.
func (b block) Bounds() (s, w, n, e float64) {
	s, w, _, _ = b.Tiles()[0].Bounds()
	_, _, n, e = b.Tiles()[BlockTiles*BlockTiles-1].Bounds()
	return s, w, n, e
}

// splitBlock sorts the zones of b into its tiles: each zone goes to every
// tile its bounding box touches, like Overpass would have returned it for
// that tile alone (a little more at most, never less). Every tile of b is
// in the result, the empty ones too.
func splitBlock(b block, zones []Zone) map[Tile][]Zone {
	out := map[Tile][]Zone{}
	tiles := b.Tiles()
	for _, t := range tiles {
		out[t] = []Zone{}
	}
	for _, z := range zones {
		zs, zw, zn, ze, ok := geometryBounds(z.Geometry)
		if !ok {
			continue
		}
		for _, t := range tiles {
			s, w, n, e := t.Bounds()
			if zs <= n+gridEps && zn >= s-gridEps && zw <= e+gridEps && ze >= w-gridEps {
				out[t] = append(out[t], z)
			}
		}
	}
	return out
}

// geometryBounds is the bounding box of g's [lat, lon] pairs.
func geometryBounds(g Geometry) (s, w, n, e float64, ok bool) {
	var coords any
	if err := json.Unmarshal(g.Coordinates, &coords); err != nil {
		return 0, 0, 0, 0, false
	}
	s, w = math.Inf(1), math.Inf(1)
	n, e = math.Inf(-1), math.Inf(-1)
	var walk func(v any)
	walk = func(v any) {
		list, isList := v.([]any)
		if !isList {
			return
		}
		if len(list) == 2 {
			lat, ok1 := list[0].(float64)
			lon, ok2 := list[1].(float64)
			if ok1 && ok2 {
				s, n = math.Min(s, lat), math.Max(n, lat)
				w, e = math.Min(w, lon), math.Max(e, lon)
				return
			}
		}
		for _, item := range list {
			walk(item)
		}
	}
	walk(coords)
	return s, w, n, e, !math.IsInf(s, 1)
}
