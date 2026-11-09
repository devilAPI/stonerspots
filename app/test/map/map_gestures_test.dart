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
    final store = SettingsStore.memory()..setBool('map_3d', map3d);
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
  }

  MapCamera camera(WidgetTester t) =>
      MapController.of(t.element(find.byType(SpotClusterLayer))).camera;
  Offset middle(WidgetTester t) => t.getCenter(find.byType(FlutterMap));

  test('flutter_map keeps its gestures, minus wheel (and two-finger move '
      'in 3D)', () {
    final flat = mapInteractionFlags(tilted: false);
    expect(InteractiveFlag.hasScrollWheelZoom(flat), isFalse);
    expect(InteractiveFlag.hasPinchMove(flat), isTrue);
    expect(InteractiveFlag.hasPinchZoom(flat), isTrue);
    final tilted = mapInteractionFlags(tilted: true);
    expect(InteractiveFlag.hasPinchMove(tilted), isFalse);
    expect(InteractiveFlag.hasPinchZoom(tilted), isTrue);
    expect(InteractiveFlag.hasDrag(tilted), isTrue);
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
      pad.panZoomUpdate(at, pan: const Offset(0, -40)),
    );
    await t.sendEventToBinding(pad.panZoomEnd());
    await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(container.read(mapPitchProvider), closeTo(kMapPitch + 10, 1e-6));
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
    expect(tilted, greaterThan(kMapPitch + 10));
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

  testWidgets('flat: two touch fingers never tilt', (t) async {
    await pump(t);
    final at = middle(t);
    final a = await t.startGesture(at - const Offset(60, 0));
    final b = await t.startGesture(at + const Offset(60, 0));
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(0, -10));
      await b.moveBy(const Offset(0, -10));
      await t.pump();
    }
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(container.read(mapPitchProvider), kMapPitch);
  });
}
