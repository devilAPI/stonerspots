import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'germany_border.g.dart';

/// § 5 KCanG is German law, so zones exist only in Germany. Same border and
/// the same lookups as the backend (`backend/internal/zones/germany.go`).

/// Height of the latitude bands that index the border edges.
const double _bandDeg = 0.02;

class _Edge {
  const _Edge(this.aLat, this.aLon, this.bLat, this.bLon);
  final double aLat, aLon, bLat, bLon;
}

class _Border {
  _Border(List<List<LatLng>> rings) {
    for (final r in rings) {
      for (final p in r) {
        s = math.min(s, p.latitude);
        n = math.max(n, p.latitude);
        w = math.min(w, p.longitude);
        e = math.max(e, p.longitude);
      }
    }
    bands = List.generate(_bandOf(n) + 1, (_) => <_Edge>[]);
    for (final r in rings) {
      for (var i = 0; i < r.length; i++) {
        final a = r[i], b = r[(i + 1) % r.length];
        final ed = _Edge(a.latitude, a.longitude, b.latitude, b.longitude);
        final lo = band(math.min(a.latitude, b.latitude));
        final hi = band(math.max(a.latitude, b.latitude));
        for (var k = lo; k <= hi; k++) {
          bands[k].add(ed);
        }
      }
    }
  }

  double s = double.infinity, w = double.infinity;
  double n = double.negativeInfinity, e = double.negativeInfinity;
  late final List<List<_Edge>> bands;

  int _bandOf(double lat) => ((lat - s) / _bandDeg).floor();

  int band(double lat) => _bandOf(lat).clamp(0, bands.length - 1);

  bool contains(double lat, double lon) {
    if (lat < s || lat > n || lon < w || lon > e) return false;
    var inside = false;
    for (final ed in bands[band(lat)]) {
      if ((ed.aLat > lat) != (ed.bLat > lat)) {
        final x =
            ed.aLon +
            (lat - ed.aLat) * (ed.bLon - ed.aLon) / (ed.bLat - ed.aLat);
        if (lon < x) inside = !inside;
      }
    }
    return inside;
  }

  bool touches(double south, double west, double north, double east) {
    if (north < s || south > n || east < w || west > e) return false;
    for (var k = band(south); k <= band(north); k++) {
      for (final ed in bands[k]) {
        if (_segmentHitsBox(ed, south, west, north, east)) return true;
      }
    }
    // no edge in the box: wholly in or wholly out
    return contains((south + north) / 2, (west + east) / 2);
  }
}

/// Liang-Barsky clipping of the edge against the box.
bool _segmentHitsBox(_Edge ed, double s, double w, double n, double e) {
  var t0 = 0.0, t1 = 1.0;
  final dLat = ed.bLat - ed.aLat, dLon = ed.bLon - ed.aLon;
  for (final (p, q) in [
    (-dLon, ed.aLon - w),
    (dLon, e - ed.aLon),
    (-dLat, ed.aLat - s),
    (dLat, n - ed.aLat),
  ]) {
    if (p == 0) {
      if (q < 0) return false;
      continue;
    }
    final r = q / p;
    if (p < 0) {
      t0 = math.max(t0, r);
    } else {
      t1 = math.min(t1, r);
    }
    if (t0 > t1) return false;
  }
  return true;
}

/// Decodes Google's encoded polyline format (precision 1e-5).
List<LatLng> decodePolyline(String s) {
  final out = <LatLng>[];
  var i = 0, lat = 0, lon = 0;
  int next() {
    var v = 0, shift = 0;
    while (i < s.length) {
      final c = s.codeUnitAt(i++) - 63;
      v |= (c & 0x1f) << shift;
      shift += 5;
      if (c < 0x20) break;
    }
    return (v & 1) != 0 ? ~(v >> 1) : v >> 1;
  }

  while (i < s.length) {
    lat += next();
    lon += next();
    out.add(LatLng(lat / 1e5, lon / 1e5));
  }
  return out;
}

final _Border _germany = _Border([
  for (final r in kGermanyBorderRings) decodePolyline(r),
]);

/// Whether [p] lies in Germany.
bool inGermany(LatLng p) => _germany.contains(p.latitude, p.longitude);

/// Whether any part of the box lies in Germany.
bool touchesGermany(double south, double west, double north, double east) =>
    _germany.touches(south, west, north, east);
