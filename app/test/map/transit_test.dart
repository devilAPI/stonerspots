import 'package:app/features/map/transit.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _Repo implements TransitRepository {
  final asked = <LatLngBounds>[];
  Object? error;
  List<TransitStop> stops_ = const [];

  @override
  Future<List<TransitStop>> stops(LatLngBounds area) async {
    asked.add(area);
    if (error != null) throw error!;
    return stops_;
  }
}

LatLngBounds _box(double s, double w, double n, double e) =>
    LatLngBounds(LatLng(s, w), LatLng(n, e));

TransitStop _stop(String id, TransitKind kind) => TransitStop(
  id: id,
  name: 'Stop $id',
  kind: kind,
  point: const LatLng(48.137, 11.575),
);

void main() {
  test('the area is snapped to the cache grid and capped', () {
    final a = TransitController.gridArea(_box(48.130, 11.560, 48.145, 11.590));
    // padded by a quarter of the view, then out to 0.05° cells, a hair inside
    expect(a.south, closeTo(48.10, 1e-5));
    expect(a.north, closeTo(48.15, 1e-5));
    expect(a.west, closeTo(11.55, 1e-5));
    expect(a.east, closeTo(11.60, 1e-5));
    expect(a.south, greaterThan(48.10));
    expect(a.east, lessThan(11.60));

    // a huge view is cut to 0.5° around its centre
    final big = TransitController.gridArea(_box(47, 10, 49, 12));
    expect(big.north - big.south, lessThanOrEqualTo(0.5));
    expect(big.east - big.west, lessThanOrEqualTo(0.5));
    expect(big.contains(const LatLng(48, 11)), isTrue);
  });

  group('controller', () {
    late _Repo repo;
    late ProviderContainer c;
    setUp(() {
      repo = _Repo();
      c = ProviderContainer(
        overrides: [
          transitRepositoryProvider.overrideWithValue(repo),
          transitDebounceProvider.overrideWithValue(Duration.zero),
          transitRetryProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
        ],
      );
      addTearDown(c.dispose);
    });
    TransitController ctl() => c.read(transitControllerProvider.notifier);
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    final view = _box(48.130, 11.560, 48.145, 11.590);

    test('loads only from zoom 13, once per area', () async {
      ctl().onCameraMoved(view, 12);
      await settle();
      expect(repo.asked, isEmpty);

      repo.stops_ = [_stop('n1', TransitKind.tram)];
      ctl().onCameraMoved(view, 13);
      await settle();
      expect(repo.asked, hasLength(1));
      expect(c.read(transitControllerProvider).stops, hasLength(1));

      // a small pan stays inside the loaded area
      ctl().onCameraMoved(_box(48.131, 11.561, 48.146, 11.591), 14);
      await settle();
      expect(repo.asked, hasLength(1));
    });

    test('switched off, nothing is loaded; on again, it loads', () async {
      ctl().setEnabled(false);
      ctl().onCameraMoved(view, 15);
      await settle();
      expect(repo.asked, isEmpty);
      ctl().setEnabled(true);
      await settle();
      expect(repo.asked, hasLength(1));
    });

    test('a failed load is retried on its own', () async {
      repo.error = Exception('busy');
      ctl().onCameraMoved(view, 14);
      await settle();
      expect(repo.asked, hasLength(1));
      repo.error = null;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repo.asked, hasLength(2));
      expect(c.read(transitControllerProvider).stops, isEmpty);
    });

    test('a failed load is retried on the next move', () async {
      repo.error = Exception('busy');
      ctl().onCameraMoved(view, 14);
      await settle();
      repo.error = null;
      ctl().onCameraMoved(view, 14);
      await settle();
      expect(repo.asked, hasLength(2));
    });
  });

  testWidgets('bus stops show from zoom 15, the rest from 13', (t) async {
    Future<void> pump(double zoom) async {
      final repo = _Repo()
        ..stops_ = [
          _stop('tram', TransitKind.tram),
          _stop('bus', TransitKind.bus),
        ];
      await t.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            transitRepositoryProvider.overrideWithValue(repo),
            transitDebounceProvider.overrideWithValue(Duration.zero),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Consumer(
              builder: (context, ref, _) => FlutterMap(
                options: MapOptions(
                  initialCenter: const LatLng(48.137, 11.575),
                  initialZoom: zoom,
                  onMapReady: () {},
                  onPositionChanged: (cam, _) => ref
                      .read(transitControllerProvider.notifier)
                      .onCameraMoved(cam.visibleBounds, cam.zoom),
                ),
                children: const [TransitStopsLayer()],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      // load as the map would on its first move
      final el = t.element(find.byType(TransitStopsLayer));
      final cam = MapCamera.of(el);
      ProviderScope.containerOf(el)
          .read(transitControllerProvider.notifier)
          .onCameraMoved(cam.visibleBounds, cam.zoom);
      await t.pumpAndSettle();
    }

    await pump(12);
    expect(find.byKey(const ValueKey('transit-tram')), findsNothing);
    await pump(14);
    expect(find.byKey(const ValueKey('transit-tram')), findsOneWidget);
    expect(find.byKey(const ValueKey('transit-bus')), findsNothing);
    await pump(15);
    expect(find.byKey(const ValueKey('transit-bus')), findsOneWidget);
  });
}
