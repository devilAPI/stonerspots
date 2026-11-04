import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'zone_geo.dart';

/// Edge of a zone tile in degrees: the server's cache grid
/// (`backend/internal/zones/tiles.go`). The app asks for whole tiles, so
/// every request hits the server's cache the same way.
const double kZoneTileSize = 0.02;

/// Absorbs float noise on tile edges (0.02 * 2406 = 48.120000000000005).
const double _eps = 1e-7;

/// One cell of the grid.
class ZoneTileId {
  const ZoneTileId(this.y, this.x);

  factory ZoneTileId.at(double lat, double lon) => ZoneTileId(
    (lat / kZoneTileSize + _eps).floor(),
    (lon / kZoneTileSize + _eps).floor(),
  );

  final int y, x;

  double get south => y * kZoneTileSize;
  double get west => x * kZoneTileSize;
  double get north => (y + 1) * kZoneTileSize;
  double get east => (x + 1) * kZoneTileSize;

  /// The query of `GET /zones` for exactly this tile.
  Map<String, String> get query => {
    'south': south.toStringAsFixed(6),
    'west': west.toStringAsFixed(6),
    'north': north.toStringAsFixed(6),
    'east': east.toStringAsFixed(6),
  };

  @override
  bool operator ==(Object other) =>
      other is ZoneTileId && other.y == y && other.x == x;

  @override
  int get hashCode => Object.hash(y, x);

  @override
  String toString() => 'ZoneTileId($y, $x)';
}

/// The tiles covering the box, row by row (empty for an empty box).
List<ZoneTileId> tilesCovering(
  double south,
  double west,
  double north,
  double east,
) {
  final y0 = (south / kZoneTileSize + _eps).floor();
  final x0 = (west / kZoneTileSize + _eps).floor();
  final y1 = math.max(y0, (north / kZoneTileSize - _eps).ceil() - 1);
  final x1 = math.max(x0, (east / kZoneTileSize - _eps).ceil() - 1);
  return [
    for (var y = y0; y <= y1; y++)
      for (var x = x0; x <= x1; x++) ZoneTileId(y, x),
  ];
}

/// The tiles that hold every place within [metres] of [p]: usually just
/// the one [p] is in, more near a tile edge (a school across the edge is
/// only in the neighbour's data).
List<ZoneTileId> tilesAround(LatLng p, double metres) {
  final f = LocalFrame(p);
  final dLat = metres / f.metresPerDegLat;
  final dLon = metres / f.metresPerDegLon;
  return tilesCovering(
    p.latitude - dLat,
    p.longitude - dLon,
    p.latitude + dLat,
    p.longitude + dLon,
  );
}
