import 'dart:math' as math;

import 'package:app/features/map/map_compass.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Future<MapController> _pump(WidgetTester t) async {
  final controller = MapController();
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: const MapOptions(
                initialCenter: LatLng(48.1, 11.5),
                initialZoom: 12,
              ),
              children: const [],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: MapCompass(controller: controller),
            ),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return controller;
}

double _needleAngle(WidgetTester t) => t
    .widget<Transform>(
      find.ancestor(
        of: find.byKey(const Key('mapCompassNeedle')),
        matching: find.byType(Transform),
      ),
    )
    .transform
    .getRotation()
    .entry(1, 0);

void main() {
  testWidgets('the needle follows the map and a tap turns it north up', (
    t,
  ) async {
    final controller = await _pump(t);
    expect(find.byTooltip('Turn north up'), findsOneWidget);
    expect(_needleAngle(t), closeTo(0, 1e-9));

    controller.rotate(90);
    await t.pump();
    // sin(90°) in the rotation matrix: the needle turned with the map
    expect(_needleAngle(t), closeTo(math.sin(math.pi / 2), 1e-6));

    await t.tap(find.byKey(const Key('mapCompass')));
    await t.pumpAndSettle();
    expect(controller.camera.rotation, closeTo(0, 1e-6));
    expect(_needleAngle(t), closeTo(0, 1e-6));
  });

  testWidgets('it takes the short way round', (t) async {
    final controller = await _pump(t);
    controller.rotate(350);
    await t.pump();
    await t.tap(find.byKey(const Key('mapCompass')));
    // on the way: between -10° (350°) and 0, never through 180°
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    final mid = controller.camera.rotation;
    expect(mid, inInclusiveRange(-10, 0));
    expect(mid, greaterThan(-10));
    await t.pumpAndSettle();
    expect(controller.camera.rotation % 360, closeTo(0, 1e-6));
  });
}
