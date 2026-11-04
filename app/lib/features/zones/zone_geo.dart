import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'zone_models.dart';

/// Earth radius used for all zone maths: WGS84's equatorial radius, the one
/// Web Mercator (the map) and latlong2's [Distance] use, so what is drawn
/// and what is checked agree.
const double kEarthRadius = 6378137.0;

const double _deg = math.pi / 180;

/// A flat x/y frame in metres around [origin] (equirectangular: x east,
/// y north). Over the few hundred metres a zone spans, it is off by far less
/// than a metre.
class LocalFrame {
  LocalFrame(this.origin)
    : _kx = math.cos(origin.latitude * _deg) * _deg * kEarthRadius;

  final LatLng origin;
  final double _kx;
  static const double _ky = _deg * kEarthRadius;

  double x(LatLng p) => (p.longitude - origin.longitude) * _kx;
  double y(LatLng p) => (p.latitude - origin.latitude) * _ky;

  /// The point [east] and [north] metres away from [origin].
  LatLng offset(double east, double north) =>
      LatLng(origin.latitude + north / _ky, origin.longitude + east / _kx);

  /// Metres per degree of latitude / longitude here.
  double get metresPerDegLat => _ky;
  double get metresPerDegLon => _kx;
}

/// Distance in metres from (px, py) to the segment (ax, ay)-(bx, by).
double segmentDistance(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  var t = 0.0;
  if (l2 > 0) {
    t = (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  }
  final ex = px - ax - t * dx, ey = py - ay - t * dy;
  return math.sqrt(ex * ex + ey * ey);
}

/// Whether [p] lies inside the closed [ring] (even-odd rule).
bool pointInRing(LatLng p, List<LatLng> ring) {
  var inside = false;
  final x = p.longitude, y = p.latitude;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude, yi = ring[i].latitude;
    final xj = ring[j].longitude, yj = ring[j].latitude;
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

/// Distance in metres from [p] to the line through [points] (to the point,
/// when there is only one).
double distanceToLine(LatLng p, List<LatLng> points, [LocalFrame? frame]) {
  final f = frame ?? LocalFrame(p);
  final px = f.x(p), py = f.y(p);
  if (points.length == 1) {
    final dx = f.x(points[0]) - px, dy = f.y(points[0]) - py;
    return math.sqrt(dx * dx + dy * dy);
  }
  var best = double.infinity;
  var ax = f.x(points[0]), ay = f.y(points[0]);
  for (var i = 1; i < points.length; i++) {
    final bx = f.x(points[i]), by = f.y(points[i]);
    final d = segmentDistance(px, py, ax, ay, bx, by);
    if (d < best) best = d;
    ax = bx;
    ay = by;
  }
  return best;
}

/// Distance in metres from [p] to the place of [zone]; 0 inside an area.
double distanceToZone(LatLng p, Zone zone) {
  final f = LocalFrame(p);
  var best = double.infinity;
  for (final part in zone.parts) {
    if (zone.shape == ZoneShape.polygon && pointInRing(p, part)) return 0;
    final d = distanceToLine(p, part, f);
    if (d < best) best = d;
  }
  return best;
}

/// Whether the bounding box of [zone], grown by its radius and [slack]
/// metres, can contain [p] (a cheap test before [distanceToZone]).
bool _nearBox(LatLng p, Zone zone, double slack) {
  final m = zone.radius + slack;
  final dLat = m / (_deg * kEarthRadius);
  final cos = math.cos(p.latitude * _deg).clamp(0.01, 1.0);
  final dLon = dLat / cos;
  return p.latitude >= zone.south - dLat &&
      p.latitude <= zone.north + dLat &&
      p.longitude >= zone.west - dLon &&
      p.longitude <= zone.east + dLon;
}

/// One zone that [p] lies in, [distance] metres from its place.
class ZoneHit {
  const ZoneHit(this.zone, this.distance);

  final Zone zone;
  final double distance;
}

/// The zones that contain [p] (within their radius, plus [slack] metres),
/// facility zones first, nearest first.
List<ZoneHit> zonesAt(LatLng p, Iterable<Zone> zones, {double slack = 0}) {
  final hits = <ZoneHit>[];
  for (final z in zones) {
    if (!_nearBox(p, z, slack + 1)) continue;
    final d = distanceToZone(p, z);
    if (d <= z.radius + slack) hits.add(ZoneHit(z, d));
  }
  hits.sort((a, b) {
    if (a.zone.isPedestrian != b.zone.isPedestrian) {
      return a.zone.isPedestrian ? 1 : -1;
    }
    return a.distance.compareTo(b.distance);
  });
  return hits;
}
