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
        for (var i = 0; i < kWallShades; i++)
          Color.from(
            alpha: 1,
            red: (wall.r * (0.56 + 0.44 * i / (kWallShades - 1))).clamp(0, 1),
            green: (wall.g * (0.56 + 0.44 * i / (kWallShades - 1))).clamp(0, 1),
            blue: (wall.b * (0.56 + 0.44 * i / (kWallShades - 1))).clamp(0, 1),
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
    final mesh = _mesh;
    var triangles = 0;
    final roofColor = palette.roof.toARGB32();
    final shades = palette.wallShades;

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
      if (mesh.indices == 0) return;
      final v = mesh.vertices();
      canvas.drawVertices(v, BlendMode.dst, Paint());
      v.dispose();
      mesh.clear();
    }

    // world point (x, y) -> map-local -> raised ground, folded into one
    // affine map per output row: xr = ax * px + bx * py + cx, and so on
    final sxx = scale * cosR, sxy = -scale * sinR;
    final syx = scale * sinR, syy = scale * cosR;
    final ox = -c.dx * cosR + c.dy * sinR + half.dx;
    final oy = -c.dx * sinR - c.dy * cosR + half.dy;
    final xa = r[0] * sxx + r[1] * syx, xb = r[0] * sxy + r[1] * syy;
    final xc = r[0] * ox + r[1] * oy + r[3];
    final ya = r[4] * sxx + r[5] * syx, yb = r[4] * sxy + r[5] * syy;
    final yc = r[4] * ox + r[5] * oy + r[7];
    final wa = r[8] * sxx + r[9] * syx, wb = r[8] * sxy + r[9] * syy;
    final wc = r[8] * ox + r[9] * oy + r[11];
    // and the eye's distance (the screen's divisor) at the roof
    final qa = q[8] * sxx + q[9] * syx, qb = q[8] * sxy + q[9] * syy;
    final qc = q[8] * ox + q[9] * oy + q[11];

    var bx = _bx, by = _by, tx = _tx, ty = _ty;
    var walls = _walls;
    var wallKeys = _wallKeys;
    for (final i in idx) {
      final b = buildings[order[i]];
      final top = -b.height * pxPerMetre;
      final bottom = -b.minHeight * pxPerMetre;
      final pts = b.points;
      final count = pts.length ~/ 2;
      if (bx.length < count) {
        _bx = bx = Float64List(count * 2);
        _by = by = Float64List(count * 2);
        _tx = tx = Float64List(count * 2);
        _ty = ty = Float64List(count * 2);
        _walls = walls = Int32List(count * 2);
        _wallKeys = wallKeys = Float64List(count * 2);
      }
      // each corner projected once: where its foot and its top are drawn
      final r2b = r[2] * bottom, r6b = r[6] * bottom, r10b = r[10] * bottom;
      final r2t = r[2] * top, r6t = r[6] * top, r10t = r[10] * top;
      final nearTop = q[10] * top + qc;
      var tooClose = false;
      for (var k = 0; k < count; k++) {
        final px = pts[2 * k], py = pts[2 * k + 1];
        // a roof reaching the eye (zoomed far in) would be drawn torn apart
        if (qa * px + qb * py + nearTop < kNearestW) {
          tooClose = true;
          break;
        }
        final xr = xa * px + xb * py + xc;
        final yr = ya * px + yb * py + yc;
        final wr = wa * px + wb * py + wc;
        final fb = 1 / (wr + r10b), ft = 1 / (wr + r10t);
        bx[k] = (xr + r2b) * fb;
        by[k] = (yr + r6b) * fb;
        tx[k] = (xr + r2t) * ft;
        ty[k] = (yr + r6t) * ft;
      }
      if (tooClose) continue;
      // walls that face the viewer, sorted far to near (insertion sort: a
      // building has a handful)
      var nWalls = 0;
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
          final key = by[k] + by[j];
          var w = nWalls++;
          while (w > 0 && wallKeys[w - 1] > key) {
            wallKeys[w] = wallKeys[w - 1];
            walls[w] = walls[w - 1];
            w--;
          }
          wallKeys[w] = key;
          walls[w] = k * 65536 + j;
        }
        start = end;
      }
      final roof = b.roof;
      final vertices = nWalls * 4 + count;
      if (vertices > _batchVertices) continue; // huge: skip
      if (mesh.vertexCount + vertices > _batchVertices) flush();
      mesh.reserve(vertices, nWalls * 6 + roof.length);
      final pos = mesh.pos, col = mesh.col, ind = mesh.ind;
      var p = mesh.vertexCount * 2, v = mesh.vertexCount, n = mesh.indices;
      final wallShade = b.wallShades;
      for (var w = 0; w < nWalls; w++) {
        final k = walls[w] ~/ 65536, j = walls[w] % 65536;
        assert(() {
          debugWallFeet.add((by[k] + by[j]) / 2);
          return true;
        }());
        final color = shades[wallShade[k]];
        pos[p] = bx[k];
        pos[p + 1] = by[k];
        pos[p + 2] = bx[j];
        pos[p + 3] = by[j];
        pos[p + 4] = tx[j];
        pos[p + 5] = ty[j];
        pos[p + 6] = tx[k];
        pos[p + 7] = ty[k];
        p += 8;
        col[v] = color;
        col[v + 1] = color;
        col[v + 2] = color;
        col[v + 3] = color;
        ind[n] = v;
        ind[n + 1] = v + 1;
        ind[n + 2] = v + 2;
        ind[n + 3] = v;
        ind[n + 4] = v + 2;
        ind[n + 5] = v + 3;
        n += 6;
        v += 4;
      }
      final r0 = v;
      for (var k = 0; k < count; k++) {
        pos[p++] = tx[k];
        pos[p++] = ty[k];
        col[v++] = roofColor;
      }
      for (var t = 0; t < roof.length; t++) {
        ind[n++] = r0 + roof[t];
      }
      mesh
        ..vertexCount = v
        ..indices = n;
      triangles += nWalls * 2 + roof.length ~/ 3;
    }
    flush();
    canvas.restore();
    lastTriangles = triangles;
    lastBuildings = idx.length;
  }

  // Scratch space for one paint, reused by the next (painting is
  // single-threaded): projected corners, walls, and the mesh.
  static var _bx = Float64List(256), _by = Float64List(256);
  static var _tx = Float64List(256), _ty = Float64List(256);
  static var _walls = Int32List(256);
  static var _wallKeys = Float64List(256);
  static final _mesh = _Mesh();

  @override
  bool shouldRepaint(BuildingPainter old) =>
      old.camera != camera ||
      old.tilt != tilt ||
      !identical(old.buildings, buildings) ||
      old.palette != palette;
}

/// Triangles with a colour per vertex, built into buffers that grow as
/// needed and are kept for the next paint.
class _Mesh {
  Float32List pos = Float32List(8192);
  Int32List col = Int32List(4096);
  Uint16List ind = Uint16List(8192);
  int vertexCount = 0;
  int indices = 0;

  /// Room for [vertices] and [indices] more.
  void reserve(int vertices, int indices) {
    final v = vertexCount + vertices, n = this.indices + indices;
    if (v > col.length) {
      final size = math.max(v, col.length * 2);
      pos = Float32List(size * 2)..setAll(0, pos);
      col = Int32List(size)..setAll(0, col);
    }
    if (n > ind.length) {
      ind = Uint16List(math.max(n, ind.length * 2))..setAll(0, ind);
    }
  }

  ui.Vertices vertices() => ui.Vertices.raw(
    VertexMode.triangles,
    Float32List.sublistView(pos, 0, vertexCount * 2),
    colors: Int32List.sublistView(col, 0, vertexCount),
    indices: Uint16List.sublistView(ind, 0, indices),
  );

  void clear() {
    vertexCount = 0;
    indices = 0;
  }
}
