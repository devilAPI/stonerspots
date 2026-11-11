package zones

import (
	"context"
	"fmt"
	"math"
	"os"
	"runtime"
	"slices"
	"sort"

	"github.com/paulmach/osm"
	"github.com/paulmach/osm/osmpbf"
)

// Building the zones from an OpenStreetMap extract (.osm.pbf) instead of
// Overpass: the same places (kindOf) with the same geometry (zoneOf), read
// in three passes so that only what the zones need is kept in memory:
// relations first (they name the ways they are made of), then ways (they
// name their nodes), then the coordinates of just those nodes.

// candidate tells cheaply whether tags may be a zone, before kindOf builds
// a map: most of the extract (buildings, roads, ...) is not.
func candidate(tags osm.Tags) bool {
	for _, t := range tags {
		switch t.Key {
		case "smoking:cannabis":
			if t.Value == "no" {
				return true
			}
		case "amenity":
			switch t.Value {
			case "school", "kindergarten", "childcare", "social_facility", "community_centre":
				return true
			}
		case "building":
			if t.Value == "kindergarten" {
				return true
			}
		case "leisure":
			if t.Value == "playground" || slices.Contains(sportsLeisure, t.Value) {
				return true
			}
		case "highway":
			if t.Value == "pedestrian" {
				return true
			}
		}
	}
	return false
}

// zoneTags returns the tags of a zone, or nil when they are none. Pedestrian
// nodes are left out like in the Overpass query (ways and relations only).
func zoneTags(tags osm.Tags, isNode bool) map[string]string {
	if !candidate(tags) {
		return nil
	}
	m := tags.Map()
	k := kindOf(m)
	if k == "" || (isNode && k == KindPedestrian) {
		return nil
	}
	return m
}

type extractRelation struct {
	id      int64
	tags    map[string]string
	members []osm.Member
}

type extractWay struct {
	id   int64
	tags map[string]string // nil: only needed as a relation's member
	refs []int64
}

// nodeCoords holds the coordinates of the nodes the zones need, sorted by
// id, as 1e-7 degrees (as in the extract).
type nodeCoords struct {
	ids    []int64
	coords [][2]int32
	found  []bool
}

func newNodeCoords(ids []int64) *nodeCoords {
	slices.Sort(ids)
	ids = slices.Compact(ids)
	return &nodeCoords{ids: ids, coords: make([][2]int32, len(ids)), found: make([]bool, len(ids))}
}

func (c *nodeCoords) index(id int64) (int, bool) {
	if len(c.ids) == 0 || id < c.ids[0] || id > c.ids[len(c.ids)-1] {
		return 0, false
	}
	i := sort.Search(len(c.ids), func(i int) bool { return c.ids[i] >= id })
	return i, i < len(c.ids) && c.ids[i] == id
}

// set is called concurrently, each node once, so each index is written by
// one goroutine only.
func (c *nodeCoords) set(id int64, lat, lon float64) {
	if i, ok := c.index(id); ok {
		c.coords[i] = [2]int32{int32(math.Round(lat * 1e7)), int32(math.Round(lon * 1e7))}
		c.found[i] = true
	}
}

func (c *nodeCoords) point(id int64) *osmPoint {
	i, ok := c.index(id)
	if !ok || !c.found[i] {
		return nil // outside the extract: skipped, like Overpass's nulls
	}
	return &osmPoint{Lat: float64(c.coords[i][0]) / 1e7, Lon: float64(c.coords[i][1]) / 1e7}
}

func (c *nodeCoords) line(refs []int64) []*osmPoint {
	out := make([]*osmPoint, len(refs))
	for i, r := range refs {
		out[i] = c.point(r)
	}
	return out
}

// scanPBF runs one pass over the extract at path.
func scanPBF(ctx context.Context, path string, setup func(*osmpbf.Scanner), each func(osm.Object)) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	sc := osmpbf.New(ctx, f, runtime.GOMAXPROCS(0))
	defer sc.Close()
	setup(sc)
	for sc.Scan() {
		each(sc.Object())
	}
	return sc.Err()
}

// zonesFromPBF reads every zone in the extract at path.
func zonesFromPBF(ctx context.Context, path string) ([]Zone, error) {
	// 1: relations that are zones, and the ways and nodes they are made of
	var rels []extractRelation
	memberWays := map[int64]bool{}
	var nodeIDs []int64
	err := scanPBF(ctx, path, func(sc *osmpbf.Scanner) {
		sc.SkipNodes, sc.SkipWays = true, true
		sc.FilterRelation = func(r *osm.Relation) bool { return zoneTags(r.Tags, false) != nil }
	}, func(o osm.Object) {
		r, ok := o.(*osm.Relation)
		if !ok {
			return
		}
		rels = append(rels, extractRelation{id: int64(r.ID), tags: r.Tags.Map(), members: r.Members})
		for _, m := range r.Members {
			switch m.Type {
			case osm.TypeWay:
				memberWays[m.Ref] = true
			case osm.TypeNode:
				nodeIDs = append(nodeIDs, m.Ref)
			}
		}
	})
	if err != nil {
		return nil, fmt.Errorf("relations: %w", err)
	}

	// 2: ways that are zones or relation members, and their nodes
	var ways []extractWay
	err = scanPBF(ctx, path, func(sc *osmpbf.Scanner) {
		sc.SkipNodes, sc.SkipRelations = true, true
		// memberWays is only read from here on, so the decoders may share it
		sc.FilterWay = func(w *osm.Way) bool {
			return memberWays[int64(w.ID)] || zoneTags(w.Tags, false) != nil
		}
	}, func(o osm.Object) {
		w, ok := o.(*osm.Way)
		if !ok {
			return
		}
		refs := make([]int64, len(w.Nodes))
		for i, n := range w.Nodes {
			refs[i] = int64(n.ID)
		}
		ways = append(ways, extractWay{id: int64(w.ID), tags: zoneTags(w.Tags, false), refs: refs})
		nodeIDs = append(nodeIDs, refs...)
	})
	if err != nil {
		return nil, fmt.Errorf("ways: %w", err)
	}

	// 3: the coordinates of those nodes, and the nodes that are zones
	coords := newNodeCoords(nodeIDs)
	nodeIDs = nil
	var zones []Zone
	err = scanPBF(ctx, path, func(sc *osmpbf.Scanner) {
		sc.SkipWays, sc.SkipRelations = true, true
		sc.FilterNode = func(n *osm.Node) bool {
			coords.set(int64(n.ID), n.Lat, n.Lon)
			return len(n.Tags) > 0 && zoneTags(n.Tags, true) != nil
		}
	}, func(o osm.Object) {
		n, ok := o.(*osm.Node)
		if !ok {
			return
		}
		lat, lon := n.Lat, n.Lon
		el := osmElement{Type: "node", ID: int64(n.ID), Lat: &lat, Lon: &lon, Tags: n.Tags.Map()}
		if z, ok := zoneOf(el); ok {
			zones = append(zones, z)
		}
	})
	if err != nil {
		return nil, fmt.Errorf("nodes: %w", err)
	}

	byID := make(map[int64]*extractWay, len(memberWays))
	for i := range ways {
		w := &ways[i]
		if memberWays[w.id] {
			byID[w.id] = w
		}
		if w.tags == nil {
			continue
		}
		el := osmElement{Type: "way", ID: w.id, Tags: w.tags, Geometry: coords.line(w.refs)}
		if z, ok := zoneOf(el); ok {
			zones = append(zones, z)
		}
	}
	for _, r := range rels {
		el := osmElement{Type: "relation", ID: r.id, Tags: r.tags}
		for _, m := range r.members {
			switch m.Type {
			case osm.TypeWay:
				w, ok := byID[m.Ref]
				if !ok {
					continue // outside the extract
				}
				el.Members = append(el.Members, osmMember{Type: "way", Role: m.Role, Geometry: coords.line(w.refs)})
			case osm.TypeNode:
				if p := coords.point(m.Ref); p != nil {
					lat, lon := p.Lat, p.Lon
					el.Members = append(el.Members, osmMember{Type: "node", Role: m.Role, Lat: &lat, Lon: &lon})
				}
			}
		}
		if z, ok := zoneOf(el); ok {
			zones = append(zones, z)
		}
	}
	return zones, nil
}

// blocksOf sorts zones into the German blocks their bounding boxes touch
// (by index into zones).
func blocksOf(zones []Zone) map[block][]int32 {
	german := map[block]bool{}
	for _, b := range germanBlocks() {
		german[b] = true
	}
	size := TileSize * BlockTiles
	out := map[block][]int32{}
	for i, z := range zones {
		s, w, n, e, ok := geometryBounds(z.Geometry)
		if !ok {
			continue
		}
		y0, y1 := int(math.Floor((s-gridEps)/size)), int(math.Floor((n+gridEps)/size))
		x0, x1 := int(math.Floor((w-gridEps)/size)), int(math.Floor((e+gridEps)/size))
		for y := y0; y <= y1; y++ {
			for x := x0; x <= x1; x++ {
				if b := (block{Y: y, X: x}); german[b] {
					out[b] = append(out[b], int32(i))
				}
			}
		}
	}
	return out
}

// tilesFromZones hands every German tile, with its zones (none too), to
// each, block by block.
func tilesFromZones(ctx context.Context, zones []Zone, each func(Tile, []Zone) error) error {
	index := blocksOf(zones)
	for _, b := range germanBlocks() {
		if err := ctx.Err(); err != nil {
			return err
		}
		list := make([]Zone, 0, len(index[b]))
		for _, i := range index[b] {
			list = append(list, zones[i])
		}
		for t, z := range splitBlock(b, list) {
			if GermanyOverlap(t.Bounds()) == Outside {
				continue
			}
			if err := each(t, z); err != nil {
				return err
			}
		}
	}
	return nil
}
