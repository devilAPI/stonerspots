package zones

import "math"

// simplifyTolerance in metres: far below what a 100 m zone or a screen at
// street level can show, but it drops most of the points of curved outlines.
const simplifyTolerance = 2.0

const earthRadius = 6371008.8 // metres (mean)

// simplify runs Douglas-Peucker with tol in metres on a local flat
// projection, which is exact enough over a few hundred metres. A closed ring
// stays closed and keeps at least a triangle; otherwise it is returned as is.
func simplify(line []pt, tol float64) []pt {
	if len(line) <= 2 {
		return line
	}
	k := math.Cos(line[0][0] * math.Pi / 180)
	xy := make([][2]float64, len(line))
	for i, p := range line {
		xy[i] = [2]float64{p[1] * k * math.Pi / 180 * earthRadius, p[0] * math.Pi / 180 * earthRadius}
	}
	keep := make([]bool, len(line))
	keep[0], keep[len(line)-1] = true, true
	dp(xy, 0, len(line)-1, tol, keep)
	out := make([]pt, 0, len(line))
	for i, p := range line {
		if keep[i] {
			out = append(out, p)
		}
	}
	if closed(line) && len(out) < 4 {
		return line
	}
	return out
}

func dp(xy [][2]float64, a, b int, tol float64, keep []bool) {
	if b <= a+1 {
		return
	}
	far, idx := -1.0, -1
	for i := a + 1; i < b; i++ {
		if d := segDist(xy[i], xy[a], xy[b]); d > far {
			far, idx = d, i
		}
	}
	if far <= tol {
		return
	}
	keep[idx] = true
	dp(xy, a, idx, tol, keep)
	dp(xy, idx, b, tol, keep)
}

// segDist is the distance from p to the segment a-b (to a when a == b, as
// with the first and last point of a ring).
func segDist(p, a, b [2]float64) float64 {
	dx, dy := b[0]-a[0], b[1]-a[1]
	l2 := dx*dx + dy*dy
	t := 0.0
	if l2 > 0 {
		t = math.Max(0, math.Min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2))
	}
	return math.Hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
}
