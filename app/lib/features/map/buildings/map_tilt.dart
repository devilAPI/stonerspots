import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix3, Matrix4, Vector3;

/// The 3D view: the flat map, tilted back around the middle of the screen
/// with perspective. The map widget is made larger than the screen so the
/// far side still fills it; the point in the middle of the screen stays the
/// map's centre, so "fly to", "locate me" and the spot list work unchanged.

/// How far the map leans back in 3D, in degrees: what the 3D button goes
/// to, and the steepest a two-finger drag can make it. A drag goes down to
/// 0, the flat map; let go below [kExitPitch], it settles there.
const double kMapPitch = 45;
const double kMaxPitch = 60;
const double kExitPitch = 10;

/// Below this tilt the buildings fade out (so they never pop at 0).
const double kBuildingsFadePitch = 15;

/// Perspective strength: the eye is about this many screen heights away.
const double _eyeDistance = 1.1;

/// Above the far edge of the map a little sky stays visible; the map is at
/// most this many screen heights tall.
const double _heightFactor = 2.0;

class MapTilt {
  MapTilt({required this.screen, required double pitchDegrees})
    : pitch = pitchDegrees * math.pi / 180 {
    final w = screen.width, h = screen.height;
    final k = 1 / (_eyeDistance * h);
    // sized for the steepest pitch, so changing the angle never resizes
    // the map (and never makes it load other tiles)
    final s = math.sin(kMaxPitch * math.pi / 180);
    final mapH = h * _heightFactor;
    final farW = 1 + k * (mapH / 2) * s; // perspective divisor at the far edge
    mapSize = Size(w * farW + 2, mapH);
    mapOffset = Offset((w - mapSize.width) / 2, (h - mapSize.height) / 2);

    final perspective = Matrix4.identity()..setEntry(3, 2, k);
    matrix = Matrix4.translationValues(w / 2, h / 2, 0)
      ..multiply(perspective)
      ..rotateX(-pitch)
      ..multiply(Matrix4.translationValues(-w / 2, -h / 2, 0));
    // map-local coordinates (what flutter_map's camera uses) to the screen
    final local = matrix.clone()
      ..multiply(Matrix4.translationValues(mapOffset.dx, mapOffset.dy, 0));
    _local = local;
    _plane = _homography(local);
    _planeInv = Matrix3.copy(_plane)..invert();
  }

  final Size screen;

  /// Radians.
  final double pitch;

  /// Size of the map widget and where its top left lies on the screen
  /// before the tilt.
  late final Size mapSize;
  late final Offset mapOffset;

  /// Screen box coordinates (map widget placed at [mapOffset]) to screen.
  late final Matrix4 matrix;
  late final Matrix4 _local;

  /// The tilt of the map plane (z = 0) as a 2D projective map: map-local to
  /// screen, and back.
  late final Matrix3 _plane, _planeInv;

  static Matrix3 _homography(Matrix4 m) => Matrix3(
    // column-major: x, y and translation columns, rows x, y, w
    m.entry(0, 0),
    m.entry(1, 0),
    m.entry(3, 0),
    m.entry(0, 1),
    m.entry(1, 1),
    m.entry(3, 1),
    m.entry(0, 3),
    m.entry(1, 3),
    m.entry(3, 3),
  );

  /// Where map-local point [p] at [z] (negative: above the ground, in
  /// map pixels) appears on the screen.
  Offset toScreen(Offset p, [double z = 0]) {
    double row(int r) =>
        _local.entry(r, 0) * p.dx +
        _local.entry(r, 1) * p.dy +
        _local.entry(r, 2) * z +
        _local.entry(r, 3);
    final w = row(3);
    return Offset(row(0) / w, row(1) / w);
  }

  /// The map-local point on the ground that shows at screen point [s].
  Offset toMap(Offset s) {
    final v = _planeInv.transform(Vector3(s.dx, s.dy, 1));
    return Offset(v.x / v.z, v.y / v.z);
  }

  /// Coefficients turning a map-local point (x, y, z) into the map-local
  /// ground point that is drawn at the same screen position: with them a
  /// layer inside the tilted map can draw things that stand up from the
  /// ground. Rows x, y, w; columns x, y, z, 1.
  late final List<double> raise = () {
    final out = List<double>.filled(12, 0);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 4; c++) {
        // (planeInv * rows x, y, w of _local)[r][c]
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          final row = const [0, 1, 3][k];
          sum += _planeInv.entry(r, k) * _local.entry(row, c);
        }
        out[r * 4 + c] = sum;
      }
    }
    return out;
  }();

  /// Rows x, y, w of the map-local (x, y, z, 1) to screen projection, for
  /// tight loops (divide x and y by w).
  late final List<double> screenRows = [
    for (final r in const [0, 1, 3])
      for (var c = 0; c < 4; c++) _local.entry(r, c),
  ];

  /// The ground (map-local) points under the screen's four corners: what
  /// the screen shows of the map, a trapezoid.
  late final List<Offset> visibleGround = [
    toMap(Offset.zero),
    toMap(Offset(screen.width, 0)),
    toMap(Offset(screen.width, screen.height)),
    toMap(Offset(0, screen.height)),
  ];

  /// For a child of the tilted map: undoes the tilt, so the child is drawn
  /// (and hit) flat in screen coordinates. Only the ground plane is
  /// inverted, which is what painting and hit testing of a flat child use.
  late final Matrix4 untilt = () {
    final i = _planeInv;
    return Matrix4(
      // column-major
      i.entry(0, 0),
      i.entry(1, 0),
      0,
      i.entry(2, 0),
      i.entry(0, 1),
      i.entry(1, 1),
      0,
      i.entry(2, 1),
      0,
      0,
      1,
      0,
      i.entry(0, 2),
      i.entry(1, 2),
      0,
      i.entry(2, 2),
    );
  }();
}

/// Hands the current [MapTilt] (null: flat map) to layers inside the map.
class MapTiltScope extends InheritedWidget {
  const MapTiltScope({super.key, required this.tilt, required super.child});

  final MapTilt? tilt;

  static MapTilt? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MapTiltScope>()?.tilt;

  @override
  bool updateShouldNotify(MapTiltScope old) => old.tilt != tilt;
}

/// The map, tilted back by [pitch] degrees; 0 is the flat map, laid out
/// exactly as without this widget. Give the map a [GlobalKey]: going from
/// flat to tilted moves it into the transform, and the key keeps its state.
class TiltedMap extends StatelessWidget {
  const TiltedMap({super.key, required this.pitch, required this.child});

  final double pitch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (pitch <= 0) return MapTiltScope(tilt: null, child: child);
    return LayoutBuilder(
      builder: (context, box) {
        final tilt = MapTilt(screen: box.biggest, pitchDegrees: pitch);
        return ClipRect(
          child: Transform(
            transform: tilt.matrix,
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: tilt.mapSize.width,
              maxWidth: tilt.mapSize.width,
              minHeight: tilt.mapSize.height,
              maxHeight: tilt.mapSize.height,
              child: MapTiltScope(tilt: tilt, child: child),
            ),
          ),
        );
      },
    );
  }
}

/// A map child that stays flat on the screen while the map is tilted (the
/// zone hints, the credits). It is laid out at the screen's size.
class UntiltedMapChild extends StatelessWidget {
  const UntiltedMapChild({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tilt = MapTiltScope.of(context);
    if (tilt == null) return child;
    return Transform(
      transform: tilt.untilt,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: tilt.screen.width,
        maxWidth: tilt.screen.width,
        minHeight: tilt.screen.height,
        maxHeight: tilt.screen.height,
        child: child,
      ),
    );
  }
}
