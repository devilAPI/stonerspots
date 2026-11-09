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
import 'package:app/features/zones/zone_layer.dart';
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
        FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            onTap: (_, p) => showZonesAt(context, ref, p, zoom),
          ),
          children: const [ZoneLayer(), ZoneOverlay()],
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
      expect(find.byKey(const Key('zoneOnlyGermany')), findsNothing);
      expect(find.byKey(const Key('zoneDisclaimer')), findsNothing);
      expect(_painter(t)?.tiles ?? const [], isEmpty);
      expect(repo.asked, isEmpty);
    });

    testWidgets('street level in Germany: the buttons are there', (t) async {
      await _pumpMap(t, overridesFor(repoWith([_playground])));
      expect(find.byKey(const Key('mapZones')), findsOneWidget);
      expect(find.byKey(const Key('mapZonesInfo')), findsOneWidget);
    });

    testWidgets('zoomed out away from Germany: buttons and a hint', (t) async {
      await _pumpMap(
        t,
        overridesFor(repoWith([])),
        zoom: 10,
        center: const LatLng(41.1373, -8.6094),
      );
      expect(find.byKey(const Key('zoneOnlyGermany')), findsOneWidget);
      expect(find.byKey(const Key('zoneZoomHint')), findsNothing);
      expect(find.byKey(const Key('mapZones')), findsOneWidget);
    });

    testWidgets('map page: zooming in on Vienna hides the zone buttons', (
      t,
    ) async {
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
      // zoom 13 around the user: still shown
      expect(find.byKey(const Key('mapZones')), findsOneWidget);

      final map = t.getCenter(find.byType(FlutterMap));
      for (var i = 0; i < 2; i++) {
        await t.tapAt(map);
        await t.pump(const Duration(milliseconds: 50));
        await t.tapAt(map);
        await t.pumpAndSettle();
      }
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
    testWidgets('a tile that failed is tried again while in view', (t) async {
      final repo = repoWith([_playground])..fail = true;
      await _pumpMap(t, [
        ...overridesFor(repo),
        zoneRetryProvider.overrideWithValue(const Duration(seconds: 5)),
      ]);
      expect(find.byKey(const Key('zoneLoadFailed')), findsOneWidget);
      expect(repo.asked, hasLength(1));

      repo.fail = false; // Overpass is back
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(repo.asked, hasLength(2));
      expect(find.byKey(const Key('zoneLoadFailed')), findsNothing);
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
    testWidgets('reaching street level: the disclaimer comes first', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, accepted: false, store: store));
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      expect(find.textContaining('OpenStreetMap data'), findsOneWidget);
      expect(find.textContaining('Anbauvereinigungen'), findsOneWidget);
      expect(find.textContaining('No legal advice'), findsOneWidget);
      expect(_painter(t), isNull);
      expect(repo.asked, isEmpty);

      await t.tap(find.byKey(const Key('zoneDisclaimerOk')));
      await t.pumpAndSettle();
      expect(store.getBool('zones_disclaimer_accepted'), isTrue);
      expect(_painter(t), isNotNull);
      expect(repo.asked, hasLength(1));
    });

    testWidgets('cancel turns the zones off and shows nothing', (t) async {
      final store = SettingsStore.memory();
      final repo = repoWith([_playground]);
      await _pumpMap(t, overridesFor(repo, accepted: false, store: store));
      await t.tap(find.byKey(const Key('zoneDisclaimerCancel')));
      await t.pumpAndSettle();
      expect(store.getBool('zones_enabled'), isFalse);
      expect(store.getBool('zones_disclaimer_accepted'), isFalse);
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
      expect(find.text('No zone found in OSM data'), findsOneWidget);
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

    testWidgets('first use: the disclaimer before the chip', (t) async {
      final repo = repoWith([_playground]);
      await pumpChip(t, overridesFor(repo, accepted: false), base);
      expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
      expect(find.byKey(const Key('zoneStatus-forbidden')), findsNothing);
      expect(repo.asked, isEmpty);
      await t.tap(find.byKey(const Key('zoneDisclaimerOk')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('zoneStatus-forbidden')), findsOneWidget);
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

    testWidgets('zone data unavailable: saved without asking', (t) async {
      final api = await pumpAdd(t, FakeZonesRepository()..fail = true);
      expect(find.byKey(const Key('addSpotZoneWarning')), findsNothing);
      expect(api.created, hasLength(1));
    });
  });
}
