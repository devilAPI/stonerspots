import 'dart:convert';

import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/features/home_widgets/home_widget_sync.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _Spots implements SpotsRepository {
  @override
  Future<List<Spot>> inBounds(
    LatLngBounds bounds, {
    List<SpotTag> tags = const [],
  }) async => const [Spot(id: 9, title: 'Isar', lat: 48.14, lon: 11.58)];
}

class _Fix implements LocationService {
  _Fix(this.position);
  final LatLng? position;

  @override
  Future<LatLng?> currentPosition() async => position;
}

void main() {
  const munich = LocationLookup(LatLng(48.1372, 11.5755));

  (ProviderContainer, List<String>) start({bool supported = true}) {
    final pushed = <String>[];
    final c = ProviderContainer(
      overrides: [
        homeWidgetPushProvider.overrideWithValue(
          supported ? (json) async => pushed.add(json) : null,
        ),
        mapSpotsRepositoryProvider.overrideWithValue(_Spots()),
        mapDebounceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(c.dispose);
    c.read(homeWidgetSyncProvider);
    return (c, pushed);
  }

  Future<void> loadMap(ProviderContainer c) async {
    c
        .read(spotsControllerProvider.notifier)
        .onCameraMoved(
          LatLngBounds(const LatLng(47, 10), const LatLng(49, 12)),
        );
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }

  test('pushes the nearest spot once a position and spots are in', () async {
    final (c, pushed) = start();
    c.read(lastLocationLookupProvider.notifier).record(munich);
    expect(pushed, isEmpty);
    await loadMap(c);
    final json = jsonDecode(pushed.single) as Map<String, dynamic>;
    expect(json['id'], 9);
    expect(json['name'], 'Isar');
  });

  test('does not push the same thing twice', () async {
    final (c, pushed) = start();
    final lookups = c.read(lastLocationLookupProvider.notifier);
    lookups.record(munich);
    await loadMap(c);
    lookups.record(const LocationLookup(LatLng(48.1372, 11.5755)));
    expect(pushed, hasLength(1));
  });

  test('a failed lookup pushes the empty state', () {
    final (c, pushed) = start();
    c
        .read(lastLocationLookupProvider.notifier)
        .record(const LocationLookup(null));
    expect(jsonDecode(pushed.single), {'state': 'no_location'});
  });

  test('stays silent where there are no such widgets', () async {
    final (c, pushed) = start(supported: false);
    c.read(lastLocationLookupProvider.notifier).record(munich);
    await loadMap(c);
    expect(pushed, isEmpty);
  });

  test('only Android has them', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(homeWidgetPushProvider) != null,
        platform == TargetPlatform.android,
        reason: '$platform',
      );
    }
  });

  test('ObservedLocationService reports every answer', () async {
    final seen = <LatLng?>[];
    void report(LocationLookup l) => seen.add(l.position);
    final found = ObservedLocationService(_Fix(const LatLng(1, 2)), report);
    expect(await found.currentPosition(), const LatLng(1, 2));
    await ObservedLocationService(_Fix(null), report).currentPosition();
    expect(seen, [const LatLng(1, 2), null]);
  });
}
