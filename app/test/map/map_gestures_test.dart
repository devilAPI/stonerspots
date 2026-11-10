import 'dart:math' as math;

import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/core/settings.dart';
import 'package:app/features/map/buildings/map_tilt.dart';
import 'package:app/features/map/map_gestures.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spot_cluster_layer.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _Repo implements SpotsRepository {
  @override
  Future<List<Spot>> inBounds(
    LatLngBounds bounds, {
    List<SpotTag> tags = const [],
  }) async => const [];
}

class _Location implements LocationService {
  @override
  Future<LatLng?> currentPosition() async => const LatLng(48.1, 11.6);
}

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester t, {bool map3d = false}) async {
    t.view.physicalSize = const Size(800, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = SettingsStore.memory();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(store),
          mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MapScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    container = ProviderScope.containerOf(t.element(find.byType(MapScreen)));
    if (map3d) {
      // it always opens flat: tilt it with the 3D button
      await t.tap(find.byKey(const Key('map3d')));
      await t.pumpAndSettle();
    }
  }

  MapCamera camera(WidgetTester t) =>
      MapController.of(t.element(find.byType(SpotClusterLayer))).camera;
  Offset middle(WidgetTester t) => t.getCenter(find.byType(FlutterMap));

  test('flutter_map keeps its gestures but wheel and two-finger move', () {
    final flags = mapInteractionFlags();
    expect(InteractiveFlag.hasScrollWheelZoom(flags), isFalse);
    expect(InteractiveFlag.hasPinchMove(flags), isFalse);
    expect(InteractiveFlag.hasPinchZoom(flags), isTrue);
    expect(InteractiveFlag.hasRotate(flags), isTrue);
    expect(InteractiveFlag.hasDrag(flags), isTrue);
    final tilting = mapInteractionFlags(tilting: true);
    expect(InteractiveFlag.hasPinchZoom(tilting), isFalse);
    expect(InteractiveFlag.hasRotate(tilting), isFalse);
    expect(InteractiveFlag.hasDrag(tilting), isTrue);
  });

  testWidgets('a mouse wheel zooms', (t) async {
    await pump(t);
    final before = camera(t);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await t.sendEventToBinding(mouse.hover(middle(t)));
    await t.sendEventToBinding(mouse.scroll(const Offset(0, -120)));
    await t.pump();
    expect(camera(t).zoom, closeTo(before.zoom + 0.6, 1e-6));
  });

  testWidgets('a two-finger touchpad swipe moves the map, no zoom', (t) async {
    await pump(t);
    final before = camera(t);
    final pad = TestPointer(1, PointerDeviceKind.trackpad);
    await t.sendEventToBinding(pad.hover(middle(t)));
    await t.sendEventToBinding(pad.scroll(const Offset(0, 100)));
    await t.pump();
    final after = camera(t);
    expect(after.zoom, before.zoom);
    // content follows the fingers: swiping up shows what is further south
    expect(after.center.latitude, lessThan(before.center.latitude));
  });

  testWidgets('3D: a touchpad pan gesture moves the map', (t) async {
    await pump(t, map3d: true);
    final before = camera(t);
    final pad = TestPointer(2, PointerDeviceKind.trackpad);
    final at = middle(t);
    await t.sendEventToBinding(pad.panZoomStart(at));
    await t.sendEventToBinding(pad.panZoomUpdate(at, pan: const Offset(80, 0)));
    await t.sendEventToBinding(pad.panZoomEnd());
    await t.pump();
    expect(camera(t).center.longitude, lessThan(before.center.longitude));
    expect(container.read(mapPitchProvider), kMapPitch);
  });

  testWidgets('3D: Shift + touchpad swipe up tilts further back', (t) async {
    await pump(t, map3d: true);
    final before = camera(t);
    await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final pad = TestPointer(2, PointerDeviceKind.trackpad);
    final at = middle(t);
    await t.sendEventToBinding(pad.panZoomStart(at));
    await t.sendEventToBinding(
      pad.panZoomUpdate(at, pan: const Offset(0, -20)),
    );
    await t.sendEventToBinding(pad.panZoomEnd());
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(container.read(mapPitchProvider), closeTo(kMapPitch + 5, 1e-6));
    expect(camera(t).center, before.center);
  });

  testWidgets('3D: two fingers dragged up tilt, a pinch does not', (t) async {
    await pump(t, map3d: true);
    final at = middle(t);
    final a = await t.startGesture(at - const Offset(60, 0));
    final b = await t.startGesture(at + const Offset(60, 0));
    for (var i = 0; i < 8; i++) {
      await a.moveBy(const Offset(0, -10));
      await b.moveBy(const Offset(0, -10));
      await t.pump();
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    final tilted = container.read(mapPitchProvider);
    expect(tilted, greaterThan(kMapPitch));
    expect(tilted, lessThanOrEqualTo(kMaxPitch));

    // spreading the fingers: a zoom, not a tilt
    final c = await t.startGesture(at - const Offset(20, 0));
    final d = await t.startGesture(at + const Offset(20, 0));
    for (var i = 0; i < 8; i++) {
      await c.moveBy(const Offset(-10, 1));
      await d.moveBy(const Offset(10, 1));
      await t.pump();
    }
    await c.up();
    await d.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), tilted);
  });

  MapTilt? tiltNow(WidgetTester t) =>
      MapTiltScope.of(t.element(find.byType(SpotClusterLayer)));

  Future<(TestGesture, TestGesture)> twoFingers(WidgetTester t) async {
    final at = middle(t);
    return (
      await t.startGesture(at - const Offset(60, 0), pointer: 7),
      await t.startGesture(at + const Offset(60, 0), pointer: 8),
    );
  }

  Future<void> drag(
    WidgetTester t,
    (TestGesture, TestGesture) f,
    double dy,
    int steps,
  ) async {
    for (var i = 0; i < steps; i++) {
      await f.$1.moveBy(Offset(0, dy));
      await f.$2.moveBy(Offset(0, dy));
      await t.pump();
    }
  }

  testWidgets('2D: two fingers up go into 3D, down back to flat 2D', (t) async {
    await pump(t);
    expect(tiltNow(t), isNull);

    var f = await twoFingers(t);
    await drag(t, f, -10, 8); // 80 px up: 20 degrees
    expect(tiltNow(t), isNotNull);
    await f.$1.up();
    await f.$2.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), closeTo(20, 1e-6));

    // down again: flat while the fingers are still on the screen
    f = await twoFingers(t);
    await drag(t, f, 10, 10);
    expect(container.read(mapPitchProvider), 0);
    expect(tiltNow(t), isNull);
    await f.$1.up();
    await f.$2.up();
    await t.pumpAndSettle();
    expect(tiltNow(t), isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('turning the map with two fingers never tilts', (t) async {
    await pump(t, map3d: true);
    final at = middle(t);
    final a = await t.startGesture(at - const Offset(80, 0), pointer: 21);
    final b = await t.startGesture(at + const Offset(80, 0), pointer: 22);
    // a quarter turn: the left finger goes up, the right one down
    for (var i = 1; i <= 12; i++) {
      final angle = i * 7.5 * 3.14159265 / 180;
      final off = Offset(80 * math.cos(angle), 80 * math.sin(angle));
      await a.moveTo(at - off);
      await b.moveTo(at + off);
      await t.pump();
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), kMapPitch);

    // as hands often do: the thumb stays, the other finger turns around it
    final thumb = await t.startGesture(at, pointer: 23);
    final finger = await t.startGesture(at + const Offset(120, 0), pointer: 24);
    for (var i = 1; i <= 10; i++) {
      final angle = -i * 6 * 3.14159265 / 180; // upwards
      await finger.moveTo(
        at + Offset(120 * math.cos(angle), 120 * math.sin(angle)),
      );
      await t.pump();
    }
    await thumb.up();
    await finger.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), kMapPitch);
  });

  testWidgets('let go nearly flat: it settles to 2D', (t) async {
    await pump(t);
    final f = await twoFingers(t);
    await drag(t, f, -4, 6); // 24 px: 6 degrees
    expect(container.read(mapPitchProvider), closeTo(6, 1e-6));
    await f.$1.up();
    await f.$2.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), 0);
    expect(tiltNow(t), isNull);
  });

  testWidgets('the map keeps its place going into 3D and back', (t) async {
    await pump(t);
    final before = camera(t);
    final f = await twoFingers(t);
    await drag(t, f, -10, 8);
    expect(camera(t).center, before.center);
    expect(camera(t).zoom, before.zoom);
    await drag(t, f, 10, 8);
    await f.$1.up();
    await f.$2.up();
    await t.pumpAndSettle();
    expect(camera(t).center, before.center);
    expect(camera(t).zoom, before.zoom);
  });
}
