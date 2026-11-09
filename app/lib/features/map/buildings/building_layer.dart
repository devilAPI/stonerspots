import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'buildings.dart';
import 'map_tilt.dart';

/// Buildings show from this zoom on (they come from zoom-14 tiles).
const double kBuildingsMinZoom = 15;

/// How opaque the buildings are, so the map under them stays readable.
/// They are drawn solid into one layer that is then faded, so walls behind
/// a roof never shine through and overlaps do not get darker.
const double kBuildingOpacity = 0.65;

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

  List<(int, int)> _tilesFor(MapCamera camera) {
    final n = 1 << kBuildingTileZoom;
    final b = camera.visibleBounds;
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
    final buildings = <Building>[];
    for (final t in _tilesFor(camera)) {
      final hit = source.cached(t.$1, t.$2);
      if (hit != null) {
        buildings.addAll(hit);
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
  const BuildingPalette(this.roof, this.wall);
  final Color roof, wall;

  static const light = BuildingPalette(Color(0xFFE6E1D8), Color(0xFFBDB5A8));
  static const dark = BuildingPalette(Color(0xFF4A505A), Color(0xFF2F343C));
}

/// Draws [buildings] far to near (painter's algorithm), each as its walls
/// and then its roof, in one batch of triangles.
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

  @override
  void paint(Canvas canvas, Size size) {
    final scale = 256 * math.pow(2, camera.zoom).toDouble();
    final c = camera.projectAtZoom(camera.center);
    final half = camera.nonRotatedSize.center(Offset.zero);
    final rot = camera.rotationRad;
    final cosR = math.cos(rot), sinR = math.sin(rot);
    final latRad = camera.center.latitude * math.pi / 180;
    final pxPerMetre = scale / (_earth * math.cos(latRad));
    final r = tilt.raise;
    final w = size.width, h = size.height;
    final margin = 0.1 * math.max(w, h);

    // map-local position of a world point (as flutter_map's camera does)
    double lx(double wx, double wy) {
      final dx = wx * scale - c.dx, dy = wy * scale - c.dy;
      return dx * cosR - dy * sinR + half.dx;
    }

    double ly(double wx, double wy) {
      final dx = wx * scale - c.dx, dy = wy * scale - c.dy;
      return dx * sinR + dy * cosR + half.dy;
    }

    // visible buildings, far (small y) first
    final visible = <(double, Building)>[];
    for (final b in buildings) {
      final x = lx(b.centerX, b.centerY), y = ly(b.centerX, b.centerY);
      final rad = (b.east - b.west + b.south - b.north) * scale;
      if (x < -margin - rad || x > w + margin + rad) continue;
      if (y < -margin - rad || y > h + margin + rad) continue;
      visible.add((y, b));
    }
    visible.sort((a, b) => a.$1.compareTo(b.$1));

    final pos = _Floats();
    final col = _Ints();
    final roofColor = palette.roof.toARGB32();
    final wallBase = palette.wall;
    // light from the south-west, high
    const lightX = -0.6, lightY = 0.8;

    // ground point drawn where (x, y, z) shows
    void put(double x, double y, double z) {
      final gw = r[8] * x + r[9] * y + r[10] * z + r[11];
      pos
        ..add((r[0] * x + r[1] * y + r[2] * z + r[3]) / gw)
        ..add((r[4] * x + r[5] * y + r[6] * z + r[7]) / gw);
    }

    var xs = Float64List(256), ys = Float64List(256);
    final walls = <(double, int)>[];
    for (final (_, b) in visible) {
      final top = -b.height * pxPerMetre;
      final bottom = -b.minHeight * pxPerMetre;
      final count = b.points.length ~/ 2;
      if (xs.length < count) {
        xs = Float64List(count * 2);
        ys = Float64List(count * 2);
      }
      for (var i = 0; i < count; i++) {
        xs[i] = lx(b.points[2 * i], b.points[2 * i + 1]);
        ys[i] = ly(b.points[2 * i], b.points[2 * i + 1]);
      }
      // walls far to near within the building
      walls.clear();
      var start = 0;
      for (final end in b.ringEnds) {
        for (var i = start; i < end; i++) {
          final j = i + 1 < end ? i + 1 : start;
          walls.add(((ys[i] + ys[j]) / 2, i * 65536 + j));
        }
        start = end;
      }
      walls.sort((a, b) => a.$1.compareTo(b.$1));
      for (final (_, ij) in walls) {
        final i = ij ~/ 65536, j = ij % 65536;
        // shade by the wall's direction on the ground (either side)
        final ex = b.points[2 * j] - b.points[2 * i];
        final ey = b.points[2 * j + 1] - b.points[2 * i + 1];
        final len = math.sqrt(ex * ex + ey * ey);
        final facing = len == 0 ? 0 : (ey * lightX - ex * lightY) / len;
        final shade = 0.78 + 0.22 * facing;
        final color = Color.from(
          alpha: 1,
          red: (wallBase.r * shade).clamp(0, 1),
          green: (wallBase.g * shade).clamp(0, 1),
          blue: (wallBase.b * shade).clamp(0, 1),
        ).toARGB32();
        put(xs[i], ys[i], bottom);
        put(xs[j], ys[j], bottom);
        put(xs[j], ys[j], top);
        put(xs[i], ys[i], bottom);
        put(xs[j], ys[j], top);
        put(xs[i], ys[i], top);
        for (var k = 0; k < 6; k++) {
          col.add(color);
        }
      }
      for (final t in b.roof) {
        put(xs[t], ys[t], top);
        col.add(roofColor);
      }
    }
    lastTriangles = col.length ~/ 3;
    if (col.length == 0) return;
    final vertices = ui.Vertices.raw(
      VertexMode.triangles,
      pos.view(),
      colors: col.view(),
    );
    canvas
      ..saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromRGBO(0, 0, 0, kBuildingOpacity),
      )
      ..drawVertices(vertices, BlendMode.dst, Paint())
      ..restore();
    vertices.dispose();
  }

  @override
  bool shouldRepaint(BuildingPainter old) =>
      old.camera != camera ||
      old.tilt != tilt ||
      !identical(old.buildings, buildings) ||
      old.buildings.length != buildings.length ||
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
