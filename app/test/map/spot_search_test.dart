import 'dart:async';
import 'dart:convert';

import 'package:app/core/api_client.dart';
import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/map/map_filter_bar.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spot_preview_sheet.dart';
import 'package:app/features/map/spot_search.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../saved/saved_helpers.dart' show FakeAuth, FakeSaved;

const _bench = Spot(
  id: 1,
  title: 'Parkbank am See',
  lat: 48.137,
  lon: 11.575,
  ratingAvg: 4.5,
  ratingCount: 2,
  distanceM: 850,
);
const _meadow = Spot(id: 2, title: 'Stadtpark Wiese', lat: 52.52, lon: 13.4);

class FakeSearch implements SpotSearchRepository {
  final queries = <({String q, LatLng? near})>[];
  List<Spot> results = const [_bench, _meadow];
  Object? error;
  Completer<void>? gate;

  @override
  Future<List<Spot>> search(String query, {LatLng? near}) async {
    queries.add((q: query, near: near));
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return results;
  }
}

class _Adapter implements HttpClientAdapter {
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 4,
          'title': 'Bank',
          'lat': 48.1,
          'lon': 11.6,
          'like_count': 0,
          'rating_avg': 4,
          'rating_count': 1,
          'tags': ['view'],
          'distance_m': 1234.5,
          'created_at': '2026-11-01T10:00:00Z',
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

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

Widget _app(Widget home, List overrides) => ProviderScope(
  overrides: [...overrides],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

void main() {
  test('the API repository sends the query and the position', () async {
    final a = _Adapter();
    final api = ApiClient(
      tokenStore: TokenStore.memory(),
      baseUrl: 'http://x/api/v1',
      adapter: a,
    );
    final repo = ApiSpotSearchRepository(api);
    final list = await repo.search('bank', near: const LatLng(48.1, 11.5));
    expect(a.seen.single.path, '/spots/search');
    expect(a.seen.single.queryParameters, {
      'q': 'bank',
      'lat': 48.1,
      'lon': 11.5,
    });
    expect(list.single.title, 'Bank');
    expect(list.single.distanceM, 1234.5);
    expect(list.single.ratingCount, 1);

    await repo.search('bank');
    expect(a.seen.last.queryParameters, {'q': 'bank'});
  });

  group('controller', () {
    late FakeSearch search;
    late ProviderContainer c;

    setUp(() {
      search = FakeSearch();
      c = ProviderContainer(
        overrides: [
          spotSearchRepositoryProvider.overrideWithValue(search),
          spotSearchDebounceProvider.overrideWithValue(
            const Duration(milliseconds: 50),
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(spotSearchControllerProvider, (_, _) {});
    });

    SpotSearchController ctrl() =>
        c.read(spotSearchControllerProvider.notifier);
    SpotSearchState state() => c.read(spotSearchControllerProvider);

    test('waits for typing to pause, then asks once', () async {
      ctrl().setQuery('p');
      expect(state().tooShort, isTrue);
      ctrl().setQuery('pa');
      ctrl().setQuery('par');
      ctrl().setQuery('  park   bank ');
      expect(state().loading, isTrue);
      expect(search.queries, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(search.queries.map((q) => q.q), ['park bank']);
      expect(state().loading, isFalse);
      expect(state().results, hasLength(2));
    });

    test('a single character never goes out', () async {
      ctrl().setQuery('ü');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(search.queries, isEmpty);
      expect(state().tooShort, isTrue);
      ctrl().setQuery('');
      expect(state().tooShort, isFalse);
      expect(state().query, '');
    });

    test('uses the position the map already has', () async {
      c
          .read(lastLocationLookupProvider.notifier)
          .record(const LocationLookup(LatLng(47.4, 8.5)));
      ctrl().setQuery('park');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(search.queries.single.near, const LatLng(47.4, 8.5));
    });

    test('an answer to an older query is dropped', () async {
      search.gate = Completer();
      ctrl().setQuery('park');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      ctrl().setQuery('wiese');
      search.results = const [_meadow];
      search.gate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(search.queries.map((q) => q.q), ['park', 'wiese']);
      expect(state().query, 'wiese');
      expect(state().results!.single.id, 2);
    });

    test('errors can be retried', () async {
      search.error = Exception('offline');
      ctrl().setQuery('park');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(state().error, isTrue);
      search.error = null;
      ctrl().retry();
      await Future<void>.delayed(Duration.zero);
      expect(state().error, isFalse);
      expect(state().results, hasLength(2));
      expect(search.queries, hasLength(2));
    });
  });

  group('search panel', () {
    late FakeSearch search;
    late List<Spot> picked;
    late int closed;

    Future<void> pumpPanel(WidgetTester t) async {
      search = FakeSearch();
      picked = [];
      closed = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await t.pumpWidget(
        _app(
          Scaffold(
            backgroundColor: Colors.black,
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: MapSpotSearch(
                focusNode: focus,
                onPick: picked.add,
                onClose: () => closed++,
              ),
            ),
          ),
          [
            spotSearchRepositoryProvider.overrideWithValue(search),
            spotSearchDebounceProvider.overrideWithValue(Duration.zero),
          ],
        ),
      );
    }

    Future<void> type(WidgetTester t, String text) async {
      await t.enterText(find.byKey(const Key('mapSearchField')), text);
      await t.pump();
      await t.pump();
    }

    testWidgets('shows name, distance and rating of each match', (t) async {
      await pumpPanel(t);
      expect(find.byKey(const Key('mapSearchResults')), findsNothing);
      await type(t, 'park');
      expect(find.text('Parkbank am See'), findsOneWidget);
      expect(find.text('Stadtpark Wiese'), findsOneWidget);
      expect(find.text('850 m'), findsOneWidget);
      expect(find.byKey(const Key('mapSearchDistance-2')), findsNothing);
      expect(find.text('4.5 (2)'), findsOneWidget);

      await t.tap(find.text('Stadtpark Wiese'));
      expect(picked.single.id, 2);
      expect(t.takeException(), isNull);
    });

    testWidgets('Escape closes, Enter takes the first match', (t) async {
      await pumpPanel(t);
      await type(t, 'park');
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(closed, 1);
      await t.testTextInput.receiveAction(TextInputAction.search);
      expect(picked.single.id, 1);
    });

    testWidgets('too short, no result and error states', (t) async {
      await pumpPanel(t);
      await type(t, 'p');
      expect(find.text('Type at least 2 characters'), findsOneWidget);
      expect(search.queries, isEmpty);

      search.results = const [];
      await type(t, 'xyz');
      expect(find.text('No spot with that name'), findsOneWidget);

      search.error = Exception('offline');
      await type(t, 'xyzw');
      expect(find.text('Search failed'), findsOneWidget);
      search
        ..error = null
        ..results = const [_meadow];
      await t.tap(find.byKey(const Key('mapSearchRetry')));
      await t.pump();
      await t.pump();
      expect(find.text('Stadtpark Wiese'), findsOneWidget);
      expect(find.text('Search failed'), findsNothing);

      await t.tap(find.byKey(const Key('mapSearchClear')));
      await t.pump();
      expect(find.byKey(const Key('mapSearchResults')), findsNothing);
      await t.tap(find.byKey(const Key('mapSearchClose')));
      expect(closed, 1);
    });

    testWidgets('a spinner while the answer is on its way', (t) async {
      await pumpPanel(t);
      search.gate = Completer();
      await type(t, 'park');
      expect(find.byKey(const Key('mapSearchProgress')), findsOneWidget);
      search.gate!.complete();
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('mapSearchProgress')), findsNothing);
      expect(find.text('Parkbank am See'), findsOneWidget);
    });
  });

  group('on the map', () {
    late FakeSearch search;

    Future<void> pumpMap(WidgetTester t) async {
      search = FakeSearch();
      await t.pumpWidget(
        _app(const MapScreen(), [
          mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
          spotSearchRepositoryProvider.overrideWithValue(search),
          spotSearchDebounceProvider.overrideWithValue(Duration.zero),
          savedRepositoryProvider.overrideWithValue(FakeSaved()),
          authControllerProvider.overrideWith(() => FakeAuth(null)),
        ]),
      );
      await t.pumpAndSettle();
    }

    MapCamera camera(WidgetTester t) =>
        MapCamera.of(t.element(find.byType(TileLayer)));

    testWidgets('picking a match flies there and opens its card', (t) async {
      await pumpMap(t);
      expect(find.byType(MapFilterBar), findsOneWidget);
      await t.tap(find.byKey(const Key('mapSearchOpen')));
      await t.pumpAndSettle();
      expect(find.byType(MapFilterBar), findsNothing);
      expect(find.byKey(const Key('mapSearchField')), findsOneWidget);

      await t.enterText(find.byKey(const Key('mapSearchField')), 'park');
      await t.pumpAndSettle();
      await t.tap(find.text('Parkbank am See'));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('mapSearchField')), findsNothing);
      final cam = camera(t);
      expect(cam.zoom, closeTo(15, 0.01));
      expect(cam.visibleBounds.contains(const LatLng(48.137, 11.575)), isTrue);
      // above the middle, clear of the card
      final spot = cam.latLngToScreenOffset(const LatLng(48.137, 11.575));
      expect(spot.dy, lessThan(cam.nonRotatedSize.height / 2));
      final sheet = find.byType(SpotPreviewSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Parkbank am See')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('Ctrl+K and / open the search', (t) async {
      await pumpMap(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.keyK);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapSearchField')), findsOneWidget);
      final field = t.widget<TextField>(
        find.byKey(const Key('mapSearchField')),
      );
      expect(field.focusNode!.hasFocus, isTrue);

      await t.tap(find.byKey(const Key('mapSearchClose')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapSearchField')), findsNothing);

      await t.sendKeyEvent(LogicalKeyboardKey.slash);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapSearchField')), findsOneWidget);
      // typed into the field now, not taken as a shortcut
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapSearchField')), findsNothing);
    });

    testWidgets('no shortcut while a sheet lies over the map', (t) async {
      await pumpMap(t);
      await t.tap(find.byKey(const Key('mapSearchOpen')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('mapSearchField')), 'park');
      await t.pumpAndSettle();
      await t.tap(find.text('Stadtpark Wiese'));
      await t.pumpAndSettle();
      expect(find.byType(SpotPreviewSheet), findsOneWidget);

      await t.sendKeyEvent(LogicalKeyboardKey.slash);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('mapSearchField')), findsNothing);
    });
  });
}
