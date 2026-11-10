import 'dart:math' as math;

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

class ZonePainter extends CustomPainter {
  ZonePainter({
    required this.camera,
    required this.tiles,
    required this.banNow,
  });

  final MapCamera camera;
  final List<ZoneTileGraphics> tiles;
  final bool banNow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.pow(2, camera.zoom - _refZoom).toDouble();
    final view = Offset.zero & size;
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
