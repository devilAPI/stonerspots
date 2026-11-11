import 'dart:async';

import 'package:app/features/zones/germany.dart';
import 'package:app/features/map/buildings/map_tilt.dart';
import 'package:app/features/map/map_gestures.dart';
import 'package:app/core/api_client.dart';
import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/core/settings.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/add_spot_screen.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/features/zones/zone_consent.dart';
import 'package:app/features/zones/zone_layer.dart';
import 'package:app/features/zones/zone_layer_controller.dart';
import 'package:app/features/zones/zone_overlay.dart';
import 'package:app/features/zones/zone_paint.dart';
import 'package:app/features/zones/zone_models.dart';
import 'package:app/features/zones/zone_status.dart';
import 'package:app/features/zones/zone_tiles.dart';
import 'package:app/features/zones/zones_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'zone_fixtures.dart';

Widget _app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

/// A map with the zone layer and its two buttons, as on the map page.
class _ZoneMap extends ConsumerWidget {
  const _ZoneMap({required this.zoom, this.center = base});
  final double zoom;
  final LatLng center;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        // as on the map page: tilted when the pitch says so (0: flat)
        TiltedMap(
          pitch: ref.watch(mapPitchProvider),
          child: FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              onTap: (_, p) => showZonesAt(context, ref, p, zoom),
            ),
            children: const [ZoneLayer(), ZoneOverlay()],
          ),
        ),
        const Positioned(
          top: 8,
          right: 8,
          child: SizedBox(
            width: 52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [ZoneToggleButton(), ZoneInfoButton()],
            ),
          ),
        ),
      ],
    ),
  );
}

/// A server that is still fetching a tile from Overpass for the first
/// [pendingTimes] requests ("zones_pending"), then has it.
class _SlowRepo extends FakeZonesRepository {
  _SlowRepo(super.tiles, this.pendingTimes);
  int pendingTimes;

  @override
  Future<ZoneData> fetchTile(ZoneTileId tile) async {
    if (pendingTimes > 0) {
      pendingTimes--;
      asked.add(tile);
      throw ApiException(503, 'zones_pending', 'being fetched');
    }
    return super.fetchTile(tile);
  }
}

class _FixedPitch extends MapPitch {
  _FixedPitch(this.degrees);
  final double degrees;
  @override
  double build() => degrees;
}

final _playground = square(
  'way/1',
  ZoneKind.playground,
  size: 40,
  name: 'Spielplatz Musterweg',
);

Future<void> _pumpMap(
  WidgetTester t,
  List<Override> overrides, {
  double zoom = 16,
  LatLng center = base,
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(_app(overrides, _ZoneMap(zoom: zoom, center: center)));
  await t.pumpAndSettle();
}

ZonePainter? _painter(WidgetTester t) {
  final f = find.byKey(const Key('zoneLayer'));
  if (f.evaluate().isEmpty) return null;
  return t.widget<CustomPaint>(f).painter as ZonePainter;
}

class _MapRepo implements SpotsRepository {
  @override
  Future<List<Spot>> inBounds(
    LatLngBounds bounds, {
    List<SpotTag> tags = const [],
  }) async => const [];
}

class _Location implements LocationService {
  _Location([this.at]);
  final LatLng? at;
  @override
  Future<LatLng?> currentPosition() async => at ?? const LatLng(48.1, 11.6);
}

class _Auth extends AuthController {
  @override
  Future<User?> build() async =>
      const User(id: 1, email: 'a@b.c', displayName: 'A');
}

class _Api implements SpotApi {
  final created = <SpotDraft>[];
  @override
  Future<Spot> createSpot(SpotDraft d, {bool force = false}) async {
    created.add(d);
    throw ApiException(500, 'test', 'stop here');
  }

  @override
  Future<Spot> setTags(int id, List<SpotTag> tags) =>
      throw UnimplementedError();
  @override
  Future<Spot> getSpot(int id) => throw UnimplementedError();
  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) =>
      throw UnimplementedError();
  @override
  Future<void> report(String t, int id, String r) async {}
}

const _vienna = LatLng(48.2082, 16.3738);

void main() {
  group('outside Germany (§ 5 KCanG is German law)', () {
    testWidgets('street level: no zone buttons, hint, disclaimer or requests', (
      t,
    ) async {
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, accepted: false), center: _vienna);
      expect(find.byKey(const Key('mapZones')), findsNothing);
      expect(find.byKey(const Key('mapZonesInfo')), findsNothing);
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(_painter(t)?.tiles ?? const [], isEmpty);
      expect(repo.asked, isEmpty);
    });

    testWidgets('street level in Germany: the buttons are there', (t) async {
      await _pumpMap(t, overridesFor(repoWith([_playground])));
      expect(find.byKey(const Key('mapZones')), findsOneWidget);
      expect(find.byKey(const Key('mapZonesInfo')), findsOneWidget);
    });

    testWidgets('zoomed out, Germany off the screen: no buttons, no hint', (
      t,
    ) async {
      await _pumpMap(
        t,
        overridesFor(repoWith([])),
        zoom: 8,
        center: const LatLng(41.1373, -8.6094), // Porto
      );
      expect(find.byKey(const Key('mapZones')), findsNothing);
      expect(find.byKey(const Key('mapZonesInfo')), findsNothing);
      expect(find.byKey(const Key('zoneZoomHint')), findsNothing);
      expect(find.text('Zoom in to see zones'), findsNothing);
    });

    testWidgets('zoomed out with a bit of Germany in view: buttons stay', (
      t,
    ) async {
      // Salzburg at zoom 9: Bavaria is on the screen
      await _pumpMap(
        t,
        overridesFor(repoWith([])),
        zoom: 9,
        center: const LatLng(47.8095, 13.0550),
      );
      expect(find.byKey(const Key('mapZones')), findsOneWidget);
      expect(find.byKey(const Key('zoneZoomHint')), findsOneWidget);
    });

    testWidgets('map page: at Vienna (zoom 13) no zone buttons', (t) async {
      t.view.physicalSize = const Size(800, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        _app([
          ...overridesFor(FakeZonesRepository()),
          mapSpotsRepositoryProvider.overrideWithValue(_MapRepo()),
          locationServiceProvider.overrideWithValue(_Location(_vienna)),
          mapDebounceProvider.overrideWithValue(Duration.zero),
        ], const MapScreen()),
      );
      await t.pumpAndSettle();
      // zoom 13 around the user, far from Germany
      expect(find.byKey(const Key('mapZones')), findsNothing);
      expect(find.byKey(const Key('mapZonesInfo')), findsNothing);
      expect(find.byKey(const Key('map3d')), findsOneWidget);
    });

    testWidgets('3D: Germany behind the viewer, off the screen: no buttons', (
      t,
    ) async {
      // Kolding, Denmark, looking north: the German border (with its
      // waters in Flensburg Fjord) is ~65 km south, under the larger,
      // tilted map but below the screen
      const kolding = LatLng(55.49, 9.47);
      await _pumpMap(
        t,
        [
          ...overridesFor(repoWith([])),
          mapPitchProvider.overrideWith(() => _FixedPitch(kMapPitch)),
        ],
        zoom: 9.5,
        center: kolding,
      );
      final tilt = MapTiltScope.of(t.element(find.byType(ZoneLayer)));
      expect(tilt, isNotNull);
      final camera = MapCamera.of(t.element(find.byType(ZoneLayer)));
      final v = camera.visibleBounds;
      // the whole tilted map reaches into Germany, the screen does not
      expect(touchesGermany(v.south, v.west, v.north, v.east), isTrue);
      expect(find.byKey(const Key('mapZones')), findsNothing);
      expect(find.byKey(const Key('mapZonesInfo')), findsNothing);
    });

    testWidgets('a spot there has no zone chip and asks nothing', (t) async {
      final repo = repoWith([_playground]);
      await t.pumpWidget(
        _app(
          overridesFor(repo, accepted: false),
          const Scaffold(body: ZoneStatusChip(lat: 48.2082, lon: 16.3738)),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(find.textContaining('zone'), findsNothing);
      expect(repo.asked, isEmpty);
    });
  });

  group('map layer', () {
    testWidgets('a tile that failed is tried again while in view; "could not '
        'be loaded" only after three failures in a row', (t) async {
      final repo = repoWith([_playground])..fail = true;
      await _pumpMap(t, [
        ...overridesFor(repo),
        zoneQuickRetryProvider.overrideWithValue(const Duration(seconds: 5)),
        zoneRetryProvider.overrideWithValue(const Duration(seconds: 30)),
      ]);
      expect(repo.asked, hasLength(1));
      // one failure: still "loading", no error
      expect(find.byKey(const Key('zoneLoadFailed')), findsNothing);
      await t.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('zoneLoading')), findsOneWidget);
      // two quick retries, both failing: now it says so
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(seconds: 5));
      await t.pump();
      expect(repo.asked, hasLength(3));
      expect(find.byKey(const Key('zoneLoadFailed')), findsOneWidget);
      // and keeps trying, less often
      await t.pump(const Duration(seconds: 5));
      expect(repo.asked, hasLength(3));

      repo.fail = false; // Overpass is back
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(repo.asked, hasLength(4));
      expect(find.byKey(const Key('zoneLoadFailed')), findsNothing);
      expect(_painter(t)!.tiles.single.zones.single.id, 'way/1');
    });

    testWidgets('still being fetched: "loading", never "failed"', (t) async {
      final zones = repoWith([_playground]);
      final repo = _SlowRepo(zones.tiles, 2);
      await _pumpMap(t, [
        ...overridesFor(repo),
        zoneRetryProvider.overrideWithValue(const Duration(seconds: 60)),
        zonePendingRetryProvider.overrideWithValue(const Duration(seconds: 3)),
      ]);
      expect(find.byKey(const Key('zoneLoadFailed')), findsNothing);
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Loading zones…'), findsOneWidget);
      // asked again soon (not after a minute), and drawn once it is there
      await t.pump(const Duration(seconds: 3));
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
      expect(repo.asked.length, greaterThanOrEqualTo(3));
      expect(find.byKey(const Key('zoneLoadFailed')), findsNothing);
      expect(find.text('Loading zones…'), findsNothing);
      expect(_painter(t)!.tiles.single.zones.single.id, 'way/1');
    });

    testWidgets('zoomed out: a hint, no zones and no requests', (t) async {
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo), zoom: 13);
      expect(find.text('Zoom in to see zones'), findsOneWidget);
      expect(_painter(t), isNull);
      expect(find.byKey(const Key('zoneAttribution')), findsNothing);
      expect(repo.asked, isEmpty);
    });

    testWidgets(
      'zoomed in: the tile is loaded and drawn, a tap tells what it is',
      (t) async {
        final repo = repoWith([_playground]);
        await _pumpMap(t, overridesFor(repo));
        expect(repo.asked, [const ZoneTileId(2406, 578)]);
        expect(_painter(t)!.tiles.single.zones.single.id, 'way/1');
        expect(
          find.text('Zones: © OpenStreetMap contributors'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('zoneZoomHint')), findsNothing);

        await t.tapAt(t.getCenter(find.byType(FlutterMap)));
        await t.pump(const Duration(milliseconds: 500)); // double-tap timeout
        await t.pumpAndSettle();
        expect(
          find.text(
            'Spielplatz Musterweg (Playground) — 100 m no-consumption zone',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('zooming in does not tell what zone is there', (t) async {
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo));
      final centre = t.getCenter(find.byType(FlutterMap));
      // a double tap zooms in
      await t.tapAt(centre);
      await t.pump(const Duration(milliseconds: 80));
      await t.tapAt(centre);
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneTapInfo')), findsNothing);
      // two fingers: pinch
      final a = await t.startGesture(centre - const Offset(30, 0));
      final b = await t.startGesture(centre + const Offset(30, 0), pointer: 7);
      await t.pump(const Duration(milliseconds: 50));
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(40, 0));
      await t.pump(const Duration(milliseconds: 50));
      await a.up();
      await b.up();
      await t.pump(const Duration(milliseconds: 500));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneTapInfo')), findsNothing);
    });

    testWidgets('the zone notice goes away: by itself, ✕, or a tap outside', (
      t,
    ) async {
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo));
      final centre = t.getCenter(find.byType(FlutterMap));
      Future<void> tapAt(Offset p) async {
        await t.tapAt(p);
        await t.pump(const Duration(milliseconds: 500)); // double-tap timeout
        await t.pumpAndSettle();
      }

      final notice = find.byKey(const Key('zoneTapInfo'));
      // by itself after a few seconds (it has an action, so Flutter would
      // keep it until dismissed)
      await tapAt(centre);
      expect(notice, findsOneWidget);
      await t.pump(const Duration(seconds: 7));
      await t.pumpAndSettle();
      expect(notice, findsNothing);

      // the close button
      await tapAt(centre);
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      expect(notice, findsNothing);

      // a tap where there is no zone
      await tapAt(centre);
      expect(notice, findsOneWidget);
      await tapAt(centre + const Offset(0, -350));
      expect(notice, findsNothing);
    });

    testWidgets('the button turns the layer off and on; it is kept', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, store: store));
      expect(_painter(t), isNotNull);
      expect(find.byTooltip('Hide no-consumption zones'), findsOneWidget);

      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      expect(_painter(t), isNull);
      expect(find.byKey(const Key('mapZonesInfo')), findsNothing);
      expect(store.getBool('zones_enabled'), isFalse);

      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      expect(_painter(t), isNotNull);
      expect(store.getBool('zones_enabled'), isTrue);
      // already read: no disclaimer again
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
    });

    testWidgets('pedestrian zones: yellow during 7-20 h, green outside', (
      t,
    ) async {
      final repo = repoWith([square('way/9', ZoneKind.pedestrian, size: 60)]);
      await _pumpMap(
        t,
        overridesFor(repo, now: () => DateTime.utc(2026, 1, 15, 10)),
      );
      expect(_painter(t)!.banNow, isTrue);
      await t.pumpWidget(const SizedBox());
      await _pumpMap(
        t,
        overridesFor(repo, now: () => DateTime.utc(2026, 1, 15, 21)),
      );
      expect(_painter(t)!.banNow, isFalse);
    });

    testWidgets('the map page has the zone button and the zoom hint', (
      t,
    ) async {
      await t.pumpWidget(
        _app([
          ...overridesFor(FakeZonesRepository()),
          mapSpotsRepositoryProvider.overrideWithValue(_MapRepo()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
        ], const MapScreen()),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapZones')), findsOneWidget);
      expect(find.byKey(const Key('mapZonesInfo')), findsOneWidget);
      // the page opens at zoom 13 around the user
      expect(find.byKey(const Key('zoneZoomHint')), findsOneWidget);
    });
  });

  group('first-use disclaimer', () {
    testWidgets('never asked by zooming in: the zone button asks', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      // on, not read yet (e.g. from before it was remembered), at street
      // level: no dialog by itself, nothing loaded, the button is "off"
      await _pumpMap(t, overridesFor(repo, accepted: false, store: store));
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(_painter(t), isNull);
      expect(repo.asked, isEmpty);
      expect(find.byTooltip('Show no-consumption zones'), findsOneWidget);

      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      expect(find.textContaining('OpenStreetMap data'), findsOneWidget);
      expect(find.textContaining('Anbauvereinigungen'), findsOneWidget);
      expect(find.textContaining('No legal advice'), findsOneWidget);
      expect(_painter(t), isNull);
      expect(repo.asked, isEmpty);

      await t.tap(find.byKey(const Key('zoneDisclaimerOk')));
      await t.pumpAndSettle();
      expect(_painter(t), isNotNull);
      expect(repo.asked, hasLength(1));
      expect(store.getBool(kZoneDisclaimerKey), isTrue);
    });

    testWidgets('once read, a restart does not ask again', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, accepted: false, store: store));
      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('zoneDisclaimerOk')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);

      // app restart: a fresh ProviderScope over the same stored settings
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        _app([
          settingsStoreProvider.overrideWithValue(store),
          zonesRepositoryProvider.overrideWithValue(repo),
          zoneDebounceProvider.overrideWithValue(Duration.zero),
        ], const _ZoneMap(zoom: 16)),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(_painter(t), isNotNull);
    });

    testWidgets('zones are off by default', (t) async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(SettingsStore.memory()),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(zonesEnabledProvider), isFalse);
      expect(container.read(zonesAcceptedProvider), isFalse);
    });

    testWidgets('cancel turns the zones off and shows nothing', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, accepted: false, store: store));
      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('zoneDisclaimerCancel')));
      await t.pumpAndSettle();
      expect(store.getBool('zones_enabled'), isFalse);
      expect(_painter(t), isNull);
      expect(find.byKey(const Key('zoneZoomHint')), findsNothing);
      expect(repo.asked, isEmpty);
    });

    testWidgets('turning the layer on asks first, also zoomed out', (t) async {
      final store = SettingsStore.memory();
      await _pumpMap(
        t,
        overridesFor(
          FakeZonesRepository(),
          enabled: false,
          accepted: false,
          store: store,
        ),
        zoom: 12,
      );
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      await t.tap(find.byKey(const Key('mapZones')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      await t.tap(find.byKey(const Key('zoneDisclaimerOk')));
      await t.pumpAndSettle();
      expect(store.getBool('zones_enabled'), isTrue);
      expect(find.byKey(const Key('zoneZoomHint')), findsOneWidget);
    });

    testWidgets('the i button shows the text again any time', (t) async {
      await _pumpMap(t, overridesFor(FakeZonesRepository()), zoom: 12);
      await t.tap(find.byKey(const Key('mapZonesInfo')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      expect(find.byKey(const Key('zoneDisclaimerCancel')), findsNothing);
      await t.tap(find.byKey(const Key('zoneDisclaimerClose')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
    });
  });

  group('spot status chip', () {
    Future<void> pumpChip(
      WidgetTester t,
      List<Override> overrides,
      LatLng p,
    ) async {
      await t.pumpWidget(
        _app(
          overrides,
          Scaffold(
            body: Center(
              child: ZoneStatusChip(lat: p.latitude, lon: p.longitude),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('could not be checked: checked again until it can', (t) async {
      // a place with no zone at all, whose tiles the server cannot load yet
      final repo = FakeZonesRepository()..fail = true;
      await pumpChip(t, [
        ...overridesFor(repo),
        zoneStatusRetryProvider.overrideWithValue(const Duration(seconds: 30)),
      ], base);
      expect(find.byKey(const Key('zoneStatus-unknown')), findsOneWidget);

      repo.fail = false; // the server has them now
      await t.pump(const Duration(seconds: 30));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneStatus-clear')), findsOneWidget);
      expect(find.text('No zone'), findsOneWidget);
    });

    testWidgets('a tile that arrives anew is checked again', (t) async {
      // the map refreshes an older copy of the tile: the chip follows
      var now = DateTime(2026, 11, 11, 23);
      final repo = repoWith([]);
      final cache = ZoneTileCache(repo, now: () => now);
      await pumpChip(t, [
        ...overridesFor(repo),
        zoneTileCacheProvider.overrideWithValue(cache),
      ], base);
      expect(find.byKey(const Key('zoneStatus-clear')), findsOneWidget);

      final tile = ZoneTileId.at(base.latitude, base.longitude);
      repo.tiles[tile] = ZoneData(
        zones: [point('n/1', ZoneKind.sports, at(0, 20))],
      );
      now = now.add(const Duration(hours: 2));
      unawaited(cache.tile(tile)); // as the map does after a while
      await t.pumpAndSettle();
      // ignore: avoid_print
      print(
        'DBG asked ${repo.asked.length} peek ${cache.peek(tile)?.zones.length} keys ${find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('zoneStatus')).evaluate().map((e) => e.widget.key)}',
      );
      expect(find.byKey(const Key('zoneStatus-forbidden')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('red: near a playground, with kind and distance', (t) async {
      await pumpChip(
        t,
        overridesFor(repoWith([point('n/1', ZoneKind.playground, at(0, 40))])),
        base,
      );
      expect(find.byKey(const Key('zoneStatus-forbidden')), findsOneWidget);
      expect(
        find.text('In a no-consumption zone (Playground, 40 m)'),
        findsOneWidget,
      );
    });

    testWidgets('red without distance on the grounds', (t) async {
      await pumpChip(t, overridesFor(repoWith([_playground])), base);
      expect(
        find.text('In a no-consumption zone (Playground)'),
        findsOneWidget,
      );
    });

    testWidgets('yellow: pedestrian zone', (t) async {
      await pumpChip(
        t,
        overridesFor(repoWith([square('w/2', ZoneKind.pedestrian, size: 80)])),
        base,
      );
      expect(find.byKey(const Key('zoneStatus-pedestrian')), findsOneWidget);
      expect(
        find.text('Pedestrian zone: no consumption 7 am–8 pm'),
        findsOneWidget,
      );
    });

    testWidgets('green: nothing in the data', (t) async {
      await pumpChip(
        t,
        overridesFor(repoWith([point('n/1', ZoneKind.school, at(0, 300))])),
        base,
      );
      expect(find.byKey(const Key('zoneStatus-clear')), findsOneWidget);
      expect(find.text('No zone'), findsOneWidget);
    });

    testWidgets('grey: the data could not be loaded', (t) async {
      await pumpChip(t, overridesFor(FakeZonesRepository()..fail = true), base);
      expect(find.byKey(const Key('zoneStatus-unknown')), findsOneWidget);
      expect(find.text('Zones could not be checked'), findsOneWidget);
    });

    testWidgets('a tap explains the result and the source', (t) async {
      await pumpChip(t, overridesFor(repoWith([_playground])), base);
      await t.tap(find.byKey(const Key('zoneStatus-forbidden')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      expect(find.text('Spielplatz Musterweg (Playground)'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsWidgets);
    });

    testWidgets('disclaimer not read: no chip and no dialog', (t) async {
      final repo = repoWith([_playground]);
      await pumpChip(t, overridesFor(repo, accepted: false), base);
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(find.byKey(const Key('zoneStatus-forbidden')), findsNothing);
      expect(repo.asked, isEmpty);
    });

    testWidgets('zones off: no chip, no request', (t) async {
      final repo = repoWith([_playground]);
      await pumpChip(t, overridesFor(repo, enabled: false), base);
      expect(find.byType(Material), findsWidgets);
      expect(find.textContaining('zone'), findsNothing);
      expect(repo.asked, isEmpty);
    });
  });

  group('adding a spot', () {
    Future<_Api> pumpAdd(
      WidgetTester t,
      ZonesRepository repo, {
      LatLng at = base,
    }) async {
      t.view.physicalSize = const Size(500, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      await t.pumpWidget(
        _app([
          ...overridesFor(repo),
          locationServiceProvider.overrideWithValue(_Location(at)),
          authControllerProvider.overrideWith(_Auth.new),
          spotApiProvider.overrideWithValue(api),
        ], const AddSpotScreen()),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('title')), 'Bench');
      await t.pump();
      final save = find.byKey(const Key('save'));
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      return api;
    }

    testWidgets('in a zone: a warning first; cancel keeps the form', (t) async {
      final api = await pumpAdd(t, repoWith([_playground]));
      expect(find.byKey(const Key('addSpotZoneWarning')), findsOneWidget);
      expect(
        find.textContaining(
          'This place is in a no-consumption zone (Spielplatz Musterweg (Playground))',
        ),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('zoneWarningCancel')));
      await t.pumpAndSettle();
      expect(api.created, isEmpty);
    });

    testWidgets('in a zone: "add anyway" saves it (only a warning)', (t) async {
      final api = await pumpAdd(
        t,
        repoWith([point('n/5', ZoneKind.explicit, at(0, 5))]),
      );
      expect(
        find.textContaining('marked in OpenStreetMap as a place where'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('zoneAddAnyway')));
      await t.pumpAndSettle();
      expect(api.created.single.title, 'Bench');
    });

    testWidgets('no zone: saved without asking', (t) async {
      final api = await pumpAdd(t, FakeZonesRepository());
      expect(find.byKey(const Key('addSpotZoneWarning')), findsNothing);
      expect(api.created, hasLength(1));
    });

    testWidgets('outside Germany: saved without asking or loading zones', (
      t,
    ) async {
      final repo = repoWith([_playground]);
      final api = await pumpAdd(t, repo, at: _vienna);
      expect(find.byKey(const Key('addSpotZoneWarning')), findsNothing);
      expect(api.created, hasLength(1));
      expect(repo.asked, isEmpty);
    });

    testWidgets('the zone check itself failing: saved anyway, no spinner', (
      t,
    ) async {
      t.view.physicalSize = const Size(500, 2000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final api = _Api();
      await t.pumpWidget(
        _app([
          ...overridesFor(repoWith([_playground])),
          // e.g. the border data failing to load (as on the 1.0.1 web app)
          zoneTileCacheProvider.overrideWith(
            (ref) => throw StateError('zone check broken'),
          ),
          locationServiceProvider.overrideWithValue(_Location(base)),
          authControllerProvider.overrideWith(_Auth.new),
          spotApiProvider.overrideWithValue(api),
        ], const AddSpotScreen()),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('title')), 'Bench');
      await t.pump();
      final save = find.byKey(const Key('save'));
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(api.created, hasLength(1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('zone data unavailable: saved without asking', (t) async {
      final api = await pumpAdd(t, FakeZonesRepository()..fail = true);
      expect(find.byKey(const Key('addSpotZoneWarning')), findsNothing);
      expect(api.created, hasLength(1));
    });
  });
}
