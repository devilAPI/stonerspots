import 'dart:ui';

import 'package:app/features/map/buildings/map_tilt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

void main() {
  const screen = Size(400, 800);
  final tilt = MapTilt(screen: screen, pitchDegrees: kMapPitch);

  Offset local(Offset screenPoint) => tilt.toMap(screenPoint);

  test('the middle of the screen is the middle of the map', () {
    final mid = tilt.toScreen(tilt.mapSize.center(Offset.zero));
    expect(mid.dx, closeTo(200, 1e-6));
    expect(mid.dy, closeTo(400, 1e-6));
  });

  test('toMap undoes toScreen on the ground', () {
    for (final p in const [Offset(10, 20), Offset(300, 700), Offset(399, 1)]) {
      final back = tilt.toScreen(local(p));
      expect(back.dx, closeTo(p.dx, 1e-6));
      expect(back.dy, closeTo(p.dy, 1e-6));
    }
  });

  test('the map covers the screen below a thin band of sky', () {
    final top = tilt.toScreen(Offset(tilt.mapSize.width / 2, 0));
    final bottom = tilt.toScreen(
      Offset(tilt.mapSize.width / 2, tilt.mapSize.height),
    );
    expect(top.dy, inInclusiveRange(0, 0.15 * screen.height));
    expect(bottom.dy, greaterThanOrEqualTo(screen.height));
    // the far corners are still outside the screen's sides
    expect(tilt.toScreen(Offset.zero).dx, lessThanOrEqualTo(0));
  });

  test('far things are smaller', () {
    final near =
        tilt.toScreen(const Offset(100, 1500)) -
        tilt.toScreen(const Offset(0, 1500));
    final far =
        tilt.toScreen(const Offset(100, 100)) -
        tilt.toScreen(const Offset(0, 100));
    expect(far.dx, lessThan(near.dx));
  });

  test('a raised point shows above its foot, and raise() agrees', () {
    final foot = tilt.mapSize.center(Offset.zero);
    const up = -50.0; // 50 px above the ground
    final screenTop = tilt.toScreen(foot, up);
    expect(screenTop.dy, lessThan(tilt.toScreen(foot).dy));
    // the ground point drawn at the same place
    final r = tilt.raise;
    double row(int i) =>
        r[i * 4] * foot.dx +
        r[i * 4 + 1] * foot.dy +
        r[i * 4 + 2] * up +
        r[i * 4 + 3];
    final g = Offset(row(0) / row(2), row(1) / row(2));
    final again = tilt.toScreen(g);
    expect(again.dx, closeTo(screenTop.dx, 1e-6));
    expect(again.dy, closeTo(screenTop.dy, 1e-6));
  });

  test('untilt cancels the tilt for flat children', () {
    final m = tilt.matrix.clone()
      ..translateByVector3(Vector3(tilt.mapOffset.dx, tilt.mapOffset.dy, 0))
      ..multiply(tilt.untilt);
    for (final p in const [Offset(0, 0), Offset(123, 456), Offset(400, 800)]) {
      final v = m.transform3(Vector3(p.dx, p.dy, 0));
      final w = m.entry(3, 0) * p.dx + m.entry(3, 1) * p.dy + m.entry(3, 3);
      expect(v.x / w, closeTo(p.dx, 1e-6));
      expect(v.y / w, closeTo(p.dy, 1e-6));
    }
  });
}
