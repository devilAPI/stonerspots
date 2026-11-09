import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'buildings.dart';
import 'map_tilt.dart';

/// Buildings show from this zoom on (street level: every house is a few
/// pixels wide at least; further out there are too many for every frame).
const double kBuildingsMinZoom = 16;

/// How opaque the buildings are, so the map under them stays readable.
/// They are drawn solid into one layer that is then faded, so walls behind
/// a roof never shine through and overlaps do not get darker.
const double kBuildingOpacity = 0.65;

/// Points closer to the eye than this (the perspective divisor, 1 at the
/// middle of the screen) cannot be drawn sensibly: a building reaching
/// there is left out instead of being drawn torn apart.
const double kNearestW = 0.3;

/// At most this many building tiles are used for one view.
const int _maxTiles = 12;

/// Earth's circumference at the equator in metres (Web Mercator sphere).
const double _earth = 40075016.686;

/// The 3D buildings of the view, as solid blocks with their OSM height:
/// walls shaded by the direction they face, a flat roof. A layer inside
/// the tilted map ([TiltedMap]); flat (no tilt) it shows nothing.
class BuildingLayer extends ConsumerStatefulWidget {
  const BuildingLayer({super.key, this.darkBase = false});

  /// The base map is dark (dark buildings); on satellite imagery and light
  /// maps they are light.
  final bool darkBase;

  @override
  ConsumerState<BuildingLayer> createState() => _BuildingLayerState();
}

class _BuildingLayerState extends ConsumerState<BuildingLayer> {
  final _asked = <(int, int)>{};
  List<(int, int)> _loaded = const [];
  List<Building> _buildings = const [];

  static bool _sameTiles(List<(int, int)> a, List<(int, int)> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The building tiles under the screen (not the whole, larger, tilted
  /// map), the middle first.
  List<(int, int)> _tilesFor(MapCamera camera, MapTilt tilt) {
    final n = 1 << kBuildingTileZoom;
    final corners = [
      for (final g in tilt.visibleGround) camera.screenOffsetToLatLng(g),
    ];
    final b = LatLngBounds.fromPoints(corners);
    double tx(double lon) => (lon + 180) / 360 * n;
    double ty(double lat) {
      final s = math.sin(lat.clamp(-85.0, 85.0) * math.pi / 180);
      return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n;
    }

    final x0 = tx(b.west).floor(), x1 = tx(b.east).floor();
    final y0 = ty(b.north).floor(), y1 = ty(b.south).floor();
    final cx = tx(camera.center.longitude), cy = ty(camera.center.latitude);
    final tiles = [
      for (var y = y0; y <= y1; y++)
        for (var x = x0; x <= x1; x++) (x, y),
    ];
    // the middle of the view first
    tiles.sort((a, b) {
      double d((int, int) t) =>
          (t.$1 + 0.5 - cx).abs() + (t.$2 + 0.5 - cy).abs();
      return d(a).compareTo(d(b));
    });
    return tiles.take(_maxTiles).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tilt = MapTiltScope.of(context);
    final camera = MapCamera.of(context);
    if (tilt == null || camera.zoom < kBuildingsMinZoom) {
      return const SizedBox.shrink();
    }
    final source = ref.watch(buildingTileSourceProvider);
    final tiles = _tilesFor(camera, tilt);
    final loaded = <(int, int)>[];
    for (final t in tiles) {
      if (source.cached(t.$1, t.$2) != null) {
        loaded.add(t);
      } else if (_asked.add(t)) {
        source
            .tile(t.$1, t.$2)
            .then(
              (_) {
                if (mounted) setState(() {});
              },
              onError: (Object _) {
                _asked.remove(t); // asked again on the next camera change
              },
            );
      }
    }
    // the same list while the same tiles are in view (most frames)
    if (!_sameTiles(loaded, _loaded)) {
      _loaded = loaded;
      _buildings = [for (final t in loaded) ...source.cached(t.$1, t.$2)!];
    }
    final buildings = _buildings;
    return IgnorePointer(
      child: CustomPaint(
        key: const Key('buildingLayer'),
        size: camera.nonRotatedSize,
        painter: BuildingPainter(
          camera: camera,
          tilt: tilt,
          buildings: buildings,
          palette: widget.darkBase
              ? BuildingPalette.dark
              : BuildingPalette.light,
        ),
      ),
    );
  }
}

class BuildingPalette {
  BuildingPalette._(this.roof, this.wall)
    : wallShades = [
        for (var i = 0; i < 17; i++)
          Color.from(
            alpha: 1,
            red: (wall.r * (0.56 + 0.44 * i / 16)).clamp(0, 1),
            green: (wall.g * (0.56 + 0.44 * i / 16)).clamp(0, 1),
            blue: (wall.b * (0.56 + 0.44 * i / 16)).clamp(0, 1),
          ).toARGB32(),
      ];

  final Color roof, wall;

  /// The wall colour from facing away from the light (first) to facing it.
  final List<int> wallShades;

  static final light = BuildingPalette._(
    const Color(0xFFE6E1D8),
    const Color(0xFFD6CFC3),
  );
  static final dark = BuildingPalette._(
    const Color(0xFF4A505A),
    const Color(0xFF3A4049),
  );
}

/// Draws [buildings] far to near (painter's algorithm), each as the walls
/// that face the viewer and then its roof, in batches of indexed triangles.
/// Only what lands on the screen is drawn, and buildings smaller than a
/// pixel or so are left out.
class BuildingPainter extends CustomPainter {
  BuildingPainter({
    required this.camera,
    required this.tilt,
    required this.buildings,
    required this.palette,
  });

  final MapCamera camera;
  final MapTilt tilt;
  final List<Building> buildings;
  final BuildingPalette palette;

  /// Triangles drawn by the last paint (for tests).
  int lastTriangles = 0;

  /// Buildings drawn by the last paint (for tests).
  int lastBuildings = 0;

  /// The middle (map-local y) of the foot of each wall drawn last (tests).
  @visibleForTesting
  final List<double> debugWallFeet = [];

  /// Below this size on screen (pixels) a building is not drawn.
  static const double minScreenSize = 1.5;

  /// Indices are 16 bit: a batch holds at most this many vertices.
  static const int _batchVertices = 65000;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = 256 * math.pow(2, camera.zoom).toDouble();
    final c = camera.projectAtZoom(camera.center);
    final half = camera.nonRotatedSize.center(Offset.zero);
    final rot = camera.rotationRad;
    final cosR = math.cos(rot), sinR = math.sin(rot);
    final latRad = camera.center.latitude * math.pi / 180;
    final pxPerMetre = scale / (_earth * math.cos(latRad));
    final r = tilt.raise; // map-local (x, y, z) -> ground point drawn there
    final q = tilt.screenRows; // map-local (x, y, z) -> screen
    final sw = tilt.screen.width, sh = tilt.screen.height;

    // the ground the screen shows, as a box in map-local coordinates (the
    // far corners are wide; buildings are culled on the screen below)
    var gx0 = double.infinity, gy0 = double.infinity;
    var gx1 = double.negativeInfinity, gy1 = double.negativeInfinity;
    for (final g in tilt.visibleGround) {
      gx0 = math.min(gx0, g.dx);
      gx1 = math.max(gx1, g.dx);
      gy0 = math.min(gy0, g.dy);
      gy1 = math.max(gy1, g.dy);
    }

    // 1. what is on the screen, with its distance (far = small y)
    final order = <int>[];
    final keys = <double>[];
    for (var n = 0; n < buildings.length; n++) {
      final b = buildings[n];
      final wx = b.centerX * scale - c.dx, wy = b.centerY * scale - c.dy;
      final x = wx * cosR - wy * sinR + half.dx;
      final y = wx * sinR + wy * cosR + half.dy;
      final rad = (b.east - b.west + b.south - b.north) * scale * 0.5;
      final top = -b.height * pxPerMetre;
      // cheap reject on the ground first (tall buildings stick out
      // towards the far side, so allow their height there)
      if (x + rad < gx0 || x - rad > gx1) continue;
      if (y + rad < gy0 + top || y - rad > gy1) continue;
      // then on the screen: foot and roof of the centre, and the size
      final w0 = q[8] * x + q[9] * y + q[11];
      if (w0 < kNearestW) continue;
      final sx0 = (q[0] * x + q[1] * y + q[3]) / w0;
      final sy0 = (q[4] * x + q[5] * y + q[7]) / w0;
      final w1 = q[8] * x + q[9] * y + q[10] * top + q[11];
      final sy1 = (q[4] * x + q[5] * y + q[6] * top + q[7]) / w1;
      final srad = rad / w0;
      if (srad * 2 < minScreenSize) continue;
      if (sx0 + srad < 0 || sx0 - srad > sw) continue;
      if (math.max(sy0, sy1) + srad < 0 || math.min(sy0, sy1) - srad > sh) {
        continue;
      }
      order.add(n);
      keys.add(y);
    }
    final idx = List<int>.generate(order.length, (i) => i)
      ..sort((a, b) => keys[a].compareTo(keys[b]));

    debugWallFeet.clear();
    final pos = _Floats();
    final col = _Ints();
    final ind = _Shorts();
    var triangles = 0;
    final roofColor = palette.roof.toARGB32();
    final shades = palette.wallShades;
    // light from the south-west, high
    const lightX = -0.6, lightY = 0.8;

    // flattening towards 2D, the buildings fade out instead of popping
    final fade = (tilt.pitch * 180 / math.pi / kBuildingsFadePitch).clamp(
      0.0,
      1.0,
    );
    canvas.saveLayer(
      Rect.fromLTRB(gx0, gy0, gx1, gy1).intersect(Offset.zero & size),
      Paint()..color = Color.fromRGBO(0, 0, 0, kBuildingOpacity * fade),
    );
    void flush() {
      if (ind.length == 0) return;
      final v = ui.Vertices.raw(
        VertexMode.triangles,
        pos.view(),
        colors: col.view(),
        indices: ind.view(),
      );
      canvas.drawVertices(v, BlendMode.dst, Paint());
      v.dispose();
      pos.length = 0;
      col.length = 0;
      ind.length = 0;
    }

    var bx = Float64List(256), by = Float64List(256);
    var tx = Float64List(256), ty = Float64List(256);
    final walls = <int>[];
    final wallKeys = <double>[];
    for (final i in idx) {
      final b = buildings[order[i]];
      final top = -b.height * pxPerMetre;
      final bottom = -b.minHeight * pxPerMetre;
      final count = b.points.length ~/ 2;
      if (bx.length < count) {
        bx = Float64List(count * 2);
        by = Float64List(count * 2);
        tx = Float64List(count * 2);
        ty = Float64List(count * 2);
      }
      // each corner projected once: where its foot and its top are drawn
      var tooClose = false;
      for (var k = 0; k < count; k++) {
        final wx = b.points[2 * k] * scale - c.dx;
        final wy = b.points[2 * k + 1] * scale - c.dy;
        final x = wx * cosR - wy * sinR + half.dx;
        final y = wx * sinR + wy * cosR + half.dy;
        // a roof reaching the eye (zoomed far in) would be drawn torn apart
        if (q[8] * x + q[9] * y + q[10] * top + q[11] < kNearestW) {
          tooClose = true;
          break;
        }
        final xr = r[0] * x + r[1] * y + r[3];
        final yr = r[4] * x + r[5] * y + r[7];
        final wr = r[8] * x + r[9] * y + r[11];
        final wb = wr + r[10] * bottom, wt = wr + r[10] * top;
        bx[k] = (xr + r[2] * bottom) / wb;
        by[k] = (yr + r[6] * bottom) / wb;
        tx[k] = (xr + r[2] * top) / wt;
        ty[k] = (yr + r[6] * top) / wt;
      }
      if (tooClose) continue;
      // walls that face the viewer, far to near
      walls.clear();
      wallKeys.clear();
      var start = 0;
      for (final end in b.ringEnds) {
        for (var k = start; k < end; k++) {
          final j = k + 1 < end ? k + 1 : start;
          // the solid side is on the same side of every ring's direction,
          // so the sign of this turn tells whether the wall faces us
          final cross =
              (bx[j] - bx[k]) * (ty[k] - by[k]) -
              (by[j] - by[k]) * (tx[k] - bx[k]);
          if (cross <= 0) continue;
          walls.add(k * 65536 + j);
          wallKeys.add(by[k] + by[j]);
        }
        start = end;
      }
      final roofTris = b.roof.length ~/ 3;
      if (pos.length ~/ 2 + walls.length * 4 + count > _batchVertices) flush();
      if (walls.length * 4 + count > _batchVertices) continue; // huge: skip
      final wallOrder = List<int>.generate(walls.length, (k) => k)
        ..sort((a, b) => wallKeys[a].compareTo(wallKeys[b]));
      for (final w in wallOrder) {
        final k = walls[w] ~/ 65536, j = walls[w] % 65536;
        assert(() {
          debugWallFeet.add((by[k] + by[j]) / 2);
          return true;
        }());
        final ex = b.points[2 * j] - b.points[2 * k];
        final ey = b.points[2 * j + 1] - b.points[2 * k + 1];
        final len = math.sqrt(ex * ex + ey * ey);
        final facing = len == 0 ? 0.0 : (ey * lightX - ex * lightY) / len;
        final color =
            shades[((facing + 1) * 0.5 * (shades.length - 1)).round()];
        final v0 = pos.length ~/ 2;
        pos
          ..add(bx[k])
          ..add(by[k])
          ..add(bx[j])
          ..add(by[j])
          ..add(tx[j])
          ..add(ty[j])
          ..add(tx[k])
          ..add(ty[k]);
        col
          ..add(color)
          ..add(color)
          ..add(color)
          ..add(color);
        ind
          ..add(v0)
          ..add(v0 + 1)
          ..add(v0 + 2)
          ..add(v0)
          ..add(v0 + 2)
          ..add(v0 + 3);
      }
      final r0 = pos.length ~/ 2;
      for (var k = 0; k < count; k++) {
        pos
          ..add(tx[k])
          ..add(ty[k]);
        col.add(roofColor);
      }
      for (final t in b.roof) {
        ind.add(r0 + t);
      }
      triangles += walls.length * 2 + roofTris;
    }
    flush();
    canvas.restore();
    lastTriangles = triangles;
    lastBuildings = idx.length;
  }

  @override
  bool shouldRepaint(BuildingPainter old) =>
      old.camera != camera ||
      old.tilt != tilt ||
      !identical(old.buildings, buildings) ||
      old.palette != palette;
}

/// Growable typed buffers, reused between frames by nobody (a frame's
/// buffers are small enough to build anew).
class _Floats {
  Float32List _b = Float32List(4096);
  int length = 0;
  void add(double v) {
    if (length == _b.length) {
      _b = Float32List(_b.length * 2)..setAll(0, _b);
    }
    _b[length++] = v;
  }

  Float32List view() => Float32List.sublistView(_b, 0, length);
}

class _Shorts {
  Uint16List _b = Uint16List(4096);
  int length = 0;
  void add(int v) {
    if (length == _b.length) {
      _b = Uint16List(_b.length * 2)..setAll(0, _b);
    }
    _b[length++] = v;
  }

  Uint16List view() => Uint16List.sublistView(_b, 0, length);
}

class _Ints {
  Int32List _b = Int32List(2048);
  int length = 0;
  void add(int v) {
    if (length == _b.length) {
      _b = Int32List(_b.length * 2)..setAll(0, _b);
    }
    _b[length++] = v;
  }

  Int32List view() => Int32List.sublistView(_b, 0, length);
}
