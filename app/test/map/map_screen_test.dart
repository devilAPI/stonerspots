import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/map/transit.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';
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

class _Transit implements TransitRepository {
  int calls = 0;
  @override
  Future<List<TransitStop>> stops(LatLngBounds area) async {
    calls++;
    return const [];
  }
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
          transitRepositoryProvider.overrideWithValue(_Transit()),
          transitDebounceProvider.overrideWithValue(Duration.zero),
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

  testWidgets('the transit button switches the stops off and on', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
          transitRepositoryProvider.overrideWithValue(_Transit()),
          transitDebounceProvider.overrideWithValue(Duration.zero),
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
    expect(find.byTooltip('Hide public transport stops'), findsOneWidget);
    await t.tap(find.byKey(const Key('mapTransit')));
    await t.pumpAndSettle();
    expect(find.byTooltip('Show public transport stops'), findsOneWidget);
  });
}
