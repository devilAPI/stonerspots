import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/core/settings.dart';
import 'package:app/features/legal/legal_info.dart';
import 'package:app/features/legal/legal_pages.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'legal_helpers.dart';

class _Repo implements SpotsRepository {
  @override
  Future<List<Spot>> inBounds(
    LatLngBounds bounds, {
    List<SpotTag> tags = const [],
  }) async => const [];
}

class _Location implements LocationService {
  @override
  Future<LatLng?> currentPosition() async => null;
}

Future<void> pumpMap(
  WidgetTester t,
  SettingsStore store, {
  String lang = 'en',
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        mapSpotsRepositoryProvider.overrideWithValue(_Repo()),
        locationServiceProvider.overrideWithValue(_Location()),
        mapDebounceProvider.overrideWithValue(Duration.zero),
        legalRepositoryProvider.overrideWithValue(FakeLegal()),
      ],
      child: MaterialApp.router(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const MapScreen()),
            GoRoute(path: kRulesPath, builder: (_, _) => const RulesScreen()),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<SettingsStore> loadStore(
  WidgetTester t,
  Map<String, Object> values,
) async {
  SharedPreferences.setMockInitialValues(values);
  late final SettingsStore store;
  await t.runAsync(() async => store = await SettingsStore.load());
  return store;
}

void main() {
  testWidgets('first start: the notice, closed for good with "Got it"', (
    t,
  ) async {
    final store = await loadStore(t, {});
    await pumpMap(t, store);
    expect(find.byKey(const Key('zoneNotice')), findsOneWidget);
    expect(find.textContaining('OpenStreetMap data'), findsOneWidget);
    expect(find.textContaining('no legal advice'), findsOneWidget);
    expect(t.takeException(), isNull);

    await t.tap(find.byKey(const Key('zoneNoticeDismiss')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('zoneNotice')), findsNothing);
    expect(store.getBool('zone_notice_seen'), isTrue);
    final prefs = await t.runAsync(SharedPreferences.getInstance);
    expect(prefs!.getBool('zone_notice_seen'), isTrue);
  });

  testWidgets('once closed it does not come back', (t) async {
    final store = await loadStore(t, {'zone_notice_seen': true});
    await pumpMap(t, store);
    expect(find.byKey(const Key('zoneNotice')), findsNothing);
  });

  testWidgets('German, and the rules link', (t) async {
    final store = await loadStore(t, {});
    await pumpMap(t, store, lang: 'de');
    expect(find.text('Verbotszonen ohne Gewähr'), findsOneWidget);
    expect(find.textContaining('keine Rechtsberatung'), findsOneWidget);
    expect(find.textContaining('7 bis 20 Uhr'), findsOneWidget);
    await t.tap(find.byKey(const Key('zoneNoticeRules')));
    await t.pumpAndSettle();
    expect(find.byType(RulesScreen), findsOneWidget);
    // opening the rules does not count as closing the notice
    expect(store.getBool('zone_notice_seen'), isNull);
  });
}
