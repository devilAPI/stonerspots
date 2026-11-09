import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_earcut/dart_earcut.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mvt.dart';

/// Buildings for the 3D map: footprints and heights from OpenStreetMap, as
/// vector tiles by OpenFreeMap (no key, worldwide, OpenMapTiles schema,
/// buildings at zoom 14).

/// Credit shown while the 3D buildings are on.
const kBuildingsAttribution = 'OpenFreeMap © OpenMapTiles';

/// The zoom of the building tiles (OpenMapTiles has every building there).
const int kBuildingTileZoom = 14;

/// One building (or building part). Points are Web Mercator in "world"
/// units 0..1 (x east, y south), x and y interleaved, all rings one after
/// the other.
class Building {
  Building({
    required this.points,
    required this.ringEnds,
    required this.roof,
    required this.height,
    required this.minHeight,
  }) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (var i = 0; i < points.length; i += 2) {
      minX = math.min(minX, points[i]);
      maxX = math.max(maxX, points[i]);
      minY = math.min(minY, points[i + 1]);
      maxY = math.max(maxY, points[i + 1]);
    }
    west = minX;
    east = maxX;
    north = minY;
    south = maxY;
  }

  final Float64List points;

  /// Point index (not coordinate index) after the last point of each ring;
  /// a ring is closed implicitly.
  final Int32List ringEnds;

  /// The roof as triangles: three point indices each.
  final Int32List roof;

  /// Metres above ground of the roof and of the bottom (a part on stilts or
  /// an upper storey has a minimum height).
  final double height;
  final double minHeight;

  late final double west, east, north, south;

  double get centerX => (west + east) / 2;
  double get centerY => (north + south) / 2;
}

double _num(Object? v, double fallback) => switch (v) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? fallback,
  _ => fallback,
};

/// Surveyor's area of a ring in tile coordinates (y down): positive for an
/// outline, negative for a hole (MVT spec 4.3.4.4).
double _area(Int32List r) {
  var a = 0.0;
  for (var i = 0; i < r.length; i += 2) {
    final j = (i + 2) % r.length;
    a += r[i] * r[j + 1] - r[j] * r[i + 1];
  }
  return a / 2;
}

/// Triangles of a feature's roof: each outline with the holes after it.
Int32List _triangulate(List<Int32List> rings) {
  final out = <int>[];
  var base = 0; // point index of the current polygon's first point
  var i = 0;
  while (i < rings.length) {
    final coords = <double>[...rings[i].map((v) => v.toDouble())];
    final holes = <int>[];
    var j = i + 1;
    while (j < rings.length && _area(rings[j]) < 0) {
      holes.add(coords.length ~/ 2);
      coords.addAll(rings[j].map((v) => v.toDouble()));
      j++;
    }
    for (final t in Earcut.triangulateRaw(coords, holeIndices: holes)) {
      out.add(base + t);
    }
    base += coords.length ~/ 2;
    i = j;
  }
  return Int32List.fromList(out);
}

/// The buildings of tile [x]/[y] at [kBuildingTileZoom] in [bytes]. Each
/// building is kept only by the tile its centre is in, so one crossing a
/// tile edge (it is in both tiles, cut at the tile's buffer) is drawn once.
List<Building> parseBuildingTile(Uint8List bytes, int x, int y) {
  final layer = readMvtLayer(bytes, 'building');
  if (layer == null) return const [];
  final n = 1 << kBuildingTileZoom;
  final ext = layer.extent.toDouble();
  final out = <Building>[];
  for (final f in layer.features) {
    if (f.properties['hide_3d'] == true) continue;
    final height = _num(f.properties['render_height'], 5);
    final minHeight = _num(f.properties['render_min_height'], 0);
    if (height <= minHeight) continue;
    // a hole before any outline would be garbage
    final rings = f.rings.skipWhile((r) => _area(r) <= 0).toList();
    if (rings.isEmpty) continue;
    final count = rings.fold<int>(0, (s, r) => s + r.length);
    final points = Float64List(count);
    final ends = Int32List(rings.length);
    var o = 0;
    for (var k = 0; k < rings.length; k++) {
      final r = rings[k];
      for (var i = 0; i < r.length; i += 2) {
        points[o++] = (x + r[i] / ext) / n;
        points[o++] = (y + r[i + 1] / ext) / n;
      }
      ends[k] = o ~/ 2;
    }
    final b = Building(
      points: points,
      ringEnds: ends,
      roof: _triangulate(rings),
      height: height,
      minHeight: minHeight,
    );
    final cx = b.centerX * n - x, cy = b.centerY * n - y;
    if (cx < 0 || cx >= 1 || cy < 0 || cy >= 1) continue;
    out.add(b);
  }
  return out;
}

/// Loads building tiles (deduplicated, the last [maxTiles] kept in memory).
class BuildingTileSource {
  BuildingTileSource(this._dio, {this.maxTiles = 48});

  final Dio _dio;
  final int maxTiles;
  final _tiles = <(int, int), List<Building>>{}; // insertion order: LRU
  final _pending = <(int, int), Future<List<Building>>>{};
  Future<String>? _template;

  /// OpenFreeMap's tile URLs carry a dated version; its TileJSON names the
  /// current one.
  Future<String> _urlTemplate() => _template ??=
      () async {
        final r = await _dio.get<Map<String, dynamic>>(
          'https://tiles.openfreemap.org/planet',
        );
        final tiles = r.data?['tiles'];
        if (tiles is! List || tiles.isEmpty || tiles.first is! String) {
          throw const FormatException('no tile URL in the TileJSON');
        }
        return tiles.first as String;
      }().catchError((Object e) {
        _template = null; // try again next time
        throw e;
      });

  /// Buildings already loaded for the tile, or null.
  List<Building>? cached(int x, int y) => _tiles[(x, y)];

  Future<List<Building>> tile(int x, int y) {
    final key = (x, y);
    final hit = _tiles.remove(key);
    if (hit != null) {
      _tiles[key] = hit; // most recently used
      return Future.value(hit);
    }
    return _pending[key] ??= () async {
      try {
        final url = (await _urlTemplate())
            .replaceFirst('{z}', '$kBuildingTileZoom')
            .replaceFirst('{x}', '$x')
            .replaceFirst('{y}', '$y');
        final r = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final data = r.data;
        final list = data == null
            ? const <Building>[]
            : parseBuildingTile(Uint8List.fromList(data), x, y);
        _tiles[key] = list;
        while (_tiles.length > maxTiles) {
          _tiles.remove(_tiles.keys.first);
        }
        return list;
      } finally {
        _pending.remove(key);
      }
    }();
  }
}

final buildingTileSourceProvider = Provider<BuildingTileSource>(
  (ref) => BuildingTileSource(Dio()),
);
