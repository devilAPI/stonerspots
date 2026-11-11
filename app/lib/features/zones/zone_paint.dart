import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import 'zone_geo.dart';
import 'zone_models.dart';
import 'zone_tiles.dart';

/// Paths are kept in pixels at this zoom, relative to the tile's corner:
/// small numbers, so the 32-bit floats of a [Path] stay exact to well
/// under a pixel at any zoom.
const double _refZoom = 17;

const _crs = Epsg3857();

/// Translucent colours of the layer; overlapping zones do not get darker
/// (each colour is drawn opaque into one layer that is then faded).
const Color kZoneRed = Color(0xFFE53935);
const Color kZoneYellow = Color(0xFFFDD835);
const Color kZoneGreen = Color(0xFF43A047);
const int _zoneAlpha = 0x50;

/// One part of a tile's drawing: areas to fill and lines to stroke with
/// round ends and joins, which together are the geometry grown by the
/// stroke's half width.
class _Bucket {
  final fill = Path();
  final stroke = Path();
  bool hasFill = false;
  bool hasStroke = false;
  double strokeWidth = 0;
}

/// The zones of one tile, turned into paths once when the tile arrives, so
/// a frame only transforms and fills them.
class ZoneTileGraphics {
  ZoneTileGraphics._(this.tile, this.zones, this.origin, this._originPx);

  factory ZoneTileGraphics.build(ZoneTileId tile, List<Zone> zones) {
    final origin = LatLng(tile.north, tile.west);
    final g = ZoneTileGraphics._(
      tile,
      zones,
      origin,
      _crs.latLngToOffset(origin, _refZoom),
    );
    final midLat = (tile.south + tile.north) / 2;
    // metres per pixel at the reference zoom here (Web Mercator)
    final mpp =
        2 *
        math.pi *
        kEarthRadius *
        math.cos(midLat * math.pi / 180) /
        _crs.scale(_refZoom);
    for (final z in zones) {
      final b = z.isPedestrian
          ? g.pedestrian
          : z.kind == ZoneKind.explicit
          ? g.explicit
          : g.facility;
      final r = z.radius / mpp;
      b.strokeWidth = 2 * r;
      for (final part in z.parts) {
        final pts = [for (final p in part) g._local(p)];
        switch (z.shape) {
          case ZoneShape.point:
            if (r > 0) {
              b.fill.addOval(Rect.fromCircle(center: pts.first, radius: r));
              b.hasFill = true;
            }
          case ZoneShape.polygon:
            b.fill.addPolygon(pts, true);
            b.hasFill = true;
            if (r > 0) {
              b.stroke.addPolygon(pts, true);
              b.hasStroke = true;
            }
          case ZoneShape.line:
            b.stroke.addPolygon(pts, false);
            b.hasStroke = true;
        }
      }
    }
    return g;
  }

  final ZoneTileId tile;
  final List<Zone> zones;

  /// North-west corner of the tile.
  final LatLng origin;
  final Offset _originPx;

  final facility = _Bucket();
  final explicit = _Bucket();
  final pedestrian = _Bucket();

  Offset _local(LatLng p) => _crs.latLngToOffset(p, _refZoom) - _originPx;
}

/// The zones of the view, drawn once into an image that [ZonePainter]
/// then only moves and scales with the map. Drawing them is costly: every
/// outline is a stroke as wide as the 100 m around it, inside two layers,
/// which on the web (CanvasKit) took tens of milliseconds a frame while the
/// map moved. The image covers the view and half of it again on every
/// side; it is drawn anew when the tiles change, the map leaves it, or the
/// zoom has changed so much that it would look blurred or too coarse.
class ZoneRaster {
  ZoneRaster({this.pixelBudget = 6000000});

  /// The most pixels the image may have; past it, it is drawn coarser.
  final int pixelBudget;

  ui.Image? _image;
  double _zoom = 0;
  // the image's top-left corner in world pixels at [_zoom], and its size
  Offset _origin = Offset.zero;
  Size _size = Size.zero;
  List<ZoneTileGraphics>? _tiles;
  bool? _banNow;

  /// Times the image was drawn (for tests).
  int draws = 0;

  /// Pixels of the current image (for tests).
  int get imagePixels => (_image?.width ?? 0) * (_image?.height ?? 0);

  void dispose() {
    _image?.dispose();
    _image = null;
  }

  void paint(Canvas canvas, Size size, ZonePainter p, double pixelRatio) {
    final camera = p.camera;
    var scale = math.pow(2, camera.zoom - _zoom).toDouble();
    final view = camera.pixelOrigin & size;
    final current =
        _image != null &&
        p.banNow == _banNow &&
        _sameTiles(p.tiles) &&
        scale > 0.7 &&
        scale < 1.42 &&
        Rect.fromLTWH(
          _origin.dx * scale,
          _origin.dy * scale,
          _size.width * scale,
          _size.height * scale,
        ).inflate(1).contains(view.topLeft) &&
        Rect.fromLTWH(
          _origin.dx * scale,
          _origin.dy * scale,
          _size.width * scale,
          _size.height * scale,
        ).inflate(1).contains(view.bottomRight);
    if (!current) {
      final area = (Offset.zero & size).inflate(
        math.max(size.width, size.height) / 2,
      );
      final budget = math.sqrt(pixelBudget / (area.width * area.height));
      final ratio = math.min(math.min(pixelRatio, 2.0), budget);
      final recorder = ui.PictureRecorder();
      final c = Canvas(recorder)
        ..scale(ratio)
        ..translate(-area.left, -area.top);
      p.drawZones(c, area);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        math.max(1, (area.width * ratio).ceil()),
        math.max(1, (area.height * ratio).ceil()),
      );
      picture.dispose();
      _image?.dispose();
      _image = image;
      _zoom = camera.zoom;
      _origin = camera.pixelOrigin + area.topLeft;
      _size = area.size;
      _tiles = p.tiles;
      _banNow = p.banNow;
      scale = 1;
      draws++;
    }
    final image = _image!;
    canvas.drawImageRect(
      image,
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(
        _origin.dx * scale - camera.pixelOrigin.dx,
        _origin.dy * scale - camera.pixelOrigin.dy,
        _size.width * scale,
        _size.height * scale,
      ),
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  bool _sameTiles(List<ZoneTileGraphics> tiles) {
    final old = _tiles;
    if (old == null || old.length != tiles.length) return false;
    for (var i = 0; i < old.length; i++) {
      if (!identical(old[i], tiles[i])) return false;
    }
    return true;
  }
}

class ZonePainter extends CustomPainter {
  ZonePainter({
    required this.camera,
    required this.tiles,
    required this.banNow,
    this.raster,
    this.pixelRatio = 1,
  });

  final MapCamera camera;
  final List<ZoneTileGraphics> tiles;
  final bool banNow;

  /// Draws through this image cache; without it, straight onto the canvas.
  final ZoneRaster? raster;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final r = raster;
    if (r == null) {
      drawZones(canvas, Offset.zero & size);
    } else {
      r.paint(canvas, size, this, pixelRatio);
    }
  }

  /// Draws the zones that reach into [view] (in view coordinates).
  void drawZones(Canvas canvas, Rect view) {
    final scale = math.pow(2, camera.zoom - _refZoom).toDouble();
    final visible = [
      for (final t in tiles)
        if (_onScreen(t, scale, view)) t,
    ];
    if (visible.isEmpty) return;
    void group(Color color, List<_Bucket> Function(ZoneTileGraphics) of) {
      if (!visible.any((t) => of(t).any((b) => b.hasFill || b.hasStroke))) {
        return;
      }
      canvas.saveLayer(view, Paint()..color = color.withAlpha(_zoneAlpha));
      final fill = Paint()..color = color;
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final t in visible) {
        canvas.save();
        canvas.translate(
          camera.getOffsetFromOrigin(t.origin).dx,
          camera.getOffsetFromOrigin(t.origin).dy,
        );
        canvas.scale(scale);
        for (final b in of(t)) {
          if (b.hasFill) canvas.drawPath(b.fill, fill);
          if (b.hasStroke) {
            canvas.drawPath(b.stroke, stroke..strokeWidth = b.strokeWidth);
          }
        }
        canvas.restore();
      }
      canvas.restore();
    }

    group(kZoneRed, (t) => [t.facility, t.explicit]);
    group(banNow ? kZoneYellow : kZoneGreen, (t) => [t.pedestrian]);
  }

  /// The tile plus the 100 m around it overlaps the screen.
  bool _onScreen(ZoneTileGraphics t, double scale, Rect view) {
    final nw = camera.getOffsetFromOrigin(t.origin);
    final se = camera.getOffsetFromOrigin(LatLng(t.tile.south, t.tile.east));
    final margin = t.facility.strokeWidth * scale; // >= 100 m in pixels
    return Rect.fromPoints(nw, se).inflate(margin + 2).overlaps(view);
  }

  @override
  bool shouldRepaint(ZonePainter old) =>
      old.camera != camera ||
      old.banNow != banNow ||
      !identical(old.tiles, tiles) && !_sameList(old.tiles, tiles);

  static bool _sameList(List<ZoneTileGraphics> a, List<ZoneTileGraphics> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
