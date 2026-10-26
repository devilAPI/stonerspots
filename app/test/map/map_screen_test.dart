import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/map_tiles.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
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
  testWidgets('the map page switches between street map and satellite', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
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
    String url() => t.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;

    // street map by default on the map page
    expect(url(), isNot(contains('World_Imagery')));
    expect(find.byTooltip('Satellite'), findsOneWidget);

    await t.tap(find.byKey(const Key('mapLayer')));
    await t.pumpAndSettle();
    expect(url(), contains('World_Imagery'));
    expect(find.text('Esri World Imagery'), findsOneWidget);
    expect(find.byTooltip('Map'), findsOneWidget);

    await t.tap(find.byKey(const Key('mapLayer')));
    await t.pumpAndSettle();
    expect(url(), isNot(contains('World_Imagery')));
    expect(t.takeException(), isNull);
  });

  Future<void> pumpMap(WidgetTester t, String key) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
          thunderforestKeyProvider.overrideWithValue(key),
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
  }

  testWidgets('the transport map is not offered without a key', (t) async {
    await pumpMap(t, '');
    expect(find.byKey(const Key('mapTransit')), findsNothing);
  });

  testWidgets('the transport map and satellite switch each other off', (
    t,
  ) async {
    await pumpMap(t, 'tf1');
    String url() => t.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;
    expect(url(), isNot(contains('thunderforest')));

    await t.tap(find.byKey(const Key('mapTransit')));
    await t.pumpAndSettle();
    expect(url(), contains('tile.thunderforest.com/'));
    expect(find.byTooltip('Hide public transport map'), findsOneWidget);

    await t.tap(find.byKey(const Key('mapLayer')));
    await t.pumpAndSettle();
    expect(url(), contains('World_Imagery'));
    expect(find.byTooltip('Show public transport map'), findsOneWidget);

    await t.tap(find.byKey(const Key('mapTransit')));
    await t.pumpAndSettle();
    expect(url(), contains('tile.thunderforest.com/'));
    expect(find.byTooltip('Satellite'), findsOneWidget);
  });

  group('location', () {
    Future<void> pumpWith(WidgetTester t, LocationService loc) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
            locationServiceProvider.overrideWithValue(loc),
            mapDebounceProvider.overrideWithValue(Duration.zero),
            mapLocationTimeoutProvider.overrideWithValue(
              const Duration(milliseconds: 50),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MapScreen(),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 100)); // past the timeout
      await t.pumpAndSettle();
    }

    LatLng centre(WidgetTester t) =>
        MapCamera.of(t.element(find.byType(TileLayer))).center;

    testWidgets('an answer after the timeout still moves the map there', (
      t,
    ) async {
      final answer = Completer<LatLng?>();
      await pumpWith(t, _Prompt(answer));
      // the prompt is still open: overview, and no "denied" yet
      expect(find.text('Location permission denied'), findsNothing);
      expect(centre(t).latitude, closeTo(49.5, 0.01));

      answer.complete(const LatLng(48.1, 11.6));
      await t.pumpAndSettle();
      expect(centre(t).latitude, closeTo(48.1, 0.01));
      expect(centre(t).longitude, closeTo(11.6, 0.01));
      expect(find.text('Location permission denied'), findsNothing);
    });

    testWidgets('a late denial says so', (t) async {
      final answer = Completer<LatLng?>();
      await pumpWith(t, _Prompt(answer));
      answer.complete(null);
      await t.pumpAndSettle();
      expect(find.text('Location permission denied'), findsOneWidget);
    });

    testWidgets('the my-location button asks again and moves there', (t) async {
      final loc = _Prompt(Completer<LatLng?>()..complete(null));
      await pumpWith(t, loc);
      expect(find.text('Location permission denied'), findsOneWidget);

      loc.next = const LatLng(47.37, 8.54); // allowed in the site settings
      await t.tap(find.byKey(const Key('mapLocateMe')));
      await t.pumpAndSettle();
      expect(centre(t).latitude, closeTo(47.37, 0.01));
    });
  });
}

/// Location lookups like the browser's: the first waits for [first] (the
/// permission prompt), later ones answer [next].
class _Prompt implements LocationService {
  _Prompt(this.first);
  final Completer<LatLng?> first;
  LatLng? next;
  bool _asked = false;

  @override
  Future<LatLng?> currentPosition() {
    if (_asked) return Future.value(next);
    _asked = true;
    return first.future;
  }
}
