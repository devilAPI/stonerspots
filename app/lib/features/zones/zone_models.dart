import 'package:latlong2/latlong.dart';

/// What a no-consumption zone is around (KCanG § 5, Germany). The kinds
/// match `backend/internal/zones`.
enum ZoneKind {
  school,
  kindergarten,
  childcare,
  youth,
  playground,
  sports,

  /// `smoking:cannabis=no` on the place itself.
  explicit,

  /// Forbidden only between 7 and 20 h.
  pedestrian;

  static ZoneKind? fromJson(Object? v) {
    for (final k in values) {
      if (k.name == v) return k;
    }
    return null;
  }
}

/// How the place is drawn in OSM.
enum ZoneShape { point, line, polygon }

/// Distance around a facility within which consumption is forbidden: the
/// law says "within sight", which it takes as given within 100 m of the
/// entrance; like bubatzkarte, the zone is drawn around the whole outline.
const double kZoneRadius = 100;

/// Pedestrian streets mapped as lines get this half-width, so the street
/// itself can be seen and tapped.
const double kPedestrianLineHalfWidth = 5;

/// An explicit ban mapped as a point or line covers this much around it
/// (an area tagged so covers the area itself).
const double kExplicitPointRadius = 15;

/// One place from `GET /zones`.
class Zone {
  Zone({
    required this.id,
    required this.kind,
    required this.name,
    required this.shape,
    required this.parts,
  }) : radius = _radiusFor(kind, shape),
       south = _min(parts, (p) => p.latitude),
       north = _max(parts, (p) => p.latitude),
       west = _min(parts, (p) => p.longitude),
       east = _max(parts, (p) => p.longitude);

  /// Null when the kind or geometry is unknown (newer server): skipped.
  static Zone? fromJson(Map<String, dynamic> j) {
    final kind = ZoneKind.fromJson(j['kind']);
    final g = j['geometry'];
    if (kind == null || g is! Map) return null;
    try {
      final coords = g['coordinates'];
      LatLng ll(Object? p) {
        final l = p as List;
        return LatLng((l[0] as num).toDouble(), (l[1] as num).toDouble());
      }

      List<LatLng> line(Object? l) => [for (final p in l as List) ll(p)];
      final (shape, parts) = switch (g['type']) {
        'Point' => (
          ZoneShape.point,
          [
            [ll(coords)],
          ],
        ),
        'LineString' => (ZoneShape.line, [line(coords)]),
        // only outer rings are sent
        'Polygon' => (ZoneShape.polygon, [line((coords as List).first)]),
        'MultiPolygon' => (
          ZoneShape.polygon,
          [for (final poly in coords as List) line((poly as List).first)],
        ),
        _ => (null, const <List<LatLng>>[]),
      };
      if (shape == null || parts.isEmpty || parts.any((p) => p.isEmpty)) {
        return null;
      }
      return Zone(
        id: '${j['id']}',
        kind: kind,
        name: '${j['name'] ?? ''}'.trim(),
        shape: shape,
        parts: parts,
      );
    } catch (_) {
      return null;
    }
  }

  final String id;
  final ZoneKind kind;
  final String name;
  final ZoneShape shape;

  /// Points: one part of one point; lines: one part; polygons: one closed
  /// outer ring per part.
  final List<List<LatLng>> parts;

  /// Forbidden within this many metres of the geometry (inside a polygon
  /// counts as 0 m).
  final double radius;

  /// Bounding box of the geometry (without [radius]).
  final double south, west, north, east;

  bool get isPedestrian => kind == ZoneKind.pedestrian;

  static double _radiusFor(ZoneKind kind, ZoneShape shape) => switch (kind) {
    ZoneKind.pedestrian =>
      shape == ZoneShape.polygon ? 0 : kPedestrianLineHalfWidth,
    ZoneKind.explicit => shape == ZoneShape.polygon ? 0 : kExplicitPointRadius,
    _ => kZoneRadius,
  };

  static double _min(List<List<LatLng>> parts, double Function(LatLng) f) {
    var m = double.infinity;
    for (final part in parts) {
      for (final p in part) {
        if (f(p) < m) m = f(p);
      }
    }
    return m;
  }

  static double _max(List<List<LatLng>> parts, double Function(LatLng) f) {
    var m = double.negativeInfinity;
    for (final part in parts) {
      for (final p in part) {
        if (f(p) > m) m = f(p);
      }
    }
    return m;
  }
}

/// The zones of one tile (or box) as the server sent them.
class ZoneData {
  const ZoneData({required this.zones, this.stale = false});

  factory ZoneData.fromJson(Map<String, dynamic> j) => ZoneData(
    zones: [
      for (final z in (j['zones'] as List?) ?? const [])
        if (z is Map) ?Zone.fromJson(Map<String, dynamic>.from(z)),
    ],
    stale: j['stale'] == true,
  );

  final List<Zone> zones;

  /// The server could not refresh the data and sent an older copy.
  final bool stale;
}
