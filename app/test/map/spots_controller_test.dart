import 'dart:async';

import 'package:app/core/models.dart';
import 'package:app/core/location_service.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

Spot spot(int id) =>
    Spot(id: id, title: 's$id', category: 'park', lat: 50, lon: 10);

class FakeRepo implements SpotsRepository {
  final calls = <Completer<List<Spot>>>[];
  final categories = <String?>[];

  @override
  Future<List<Spot>> inBounds(LatLngBounds bounds, {String? category}) {
    categories.add(category);
    final c = Completer<List<Spot>>();
    calls.add(c);
    return c.future;
  }
}

class FakeLocation implements LocationService {
  FakeLocation(this.pos);
  final LatLng? pos;
  @override
  Future<LatLng?> currentPosition() async => pos;
}

final bounds = LatLngBounds(const LatLng(49, 9), const LatLng(51, 11));
const wait = Duration(milliseconds: 60);

ProviderContainer make(FakeRepo repo, {LatLng? pos}) {
  final c = ProviderContainer(
    overrides: [
      mapSpotsRepositoryProvider.overrideWithValue(repo),
      locationServiceProvider.overrideWithValue(FakeLocation(pos)),
      mapDebounceProvider.overrideWithValue(const Duration(milliseconds: 20)),
    ],
  );
  addTearDown(c.dispose);
  c.listen(spotsControllerProvider, (_, _) {});
  return c;
}

void main() {
  test('debounces rapid camera moves into one request', () async {
    final repo = FakeRepo();
    final c = make(repo);
    final ctrl = c.read(spotsControllerProvider.notifier);
    for (var i = 0; i < 5; i++) {
      ctrl.onCameraMoved(bounds);
    }
    await Future<void>.delayed(wait);
    expect(repo.calls, hasLength(1));
  });

  test('stale response does not overwrite newer one', () async {
    final repo = FakeRepo();
    final c = make(repo);
    final ctrl = c.read(spotsControllerProvider.notifier);
    ctrl.onCameraMoved(bounds);
    await Future<void>.delayed(wait);
    ctrl.onCameraMoved(bounds);
    await Future<void>.delayed(wait);
    expect(repo.calls, hasLength(2));
    repo.calls[1].complete([spot(2)]);
    await Future<void>.delayed(Duration.zero);
    repo.calls[0].complete([spot(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(spotsControllerProvider).spots.map((s) => s.id), [2]);
  });

  test('keeps old markers while loading', () async {
    final repo = FakeRepo();
    final c = make(repo);
    final ctrl = c.read(spotsControllerProvider.notifier);
    ctrl.onCameraMoved(bounds);
    await Future<void>.delayed(wait);
    repo.calls[0].complete([spot(1)]);
    await Future<void>.delayed(Duration.zero);
    ctrl.onCameraMoved(bounds);
    await Future<void>.delayed(wait);
    final s = c.read(spotsControllerProvider);
    expect(s.loading, isTrue);
    expect(s.spots.map((x) => x.id), [1]);
  });

  test('category change refetches immediately with the category', () async {
    final repo = FakeRepo();
    final c = make(repo);
    final ctrl = c.read(spotsControllerProvider.notifier);
    ctrl.onCameraMoved(bounds);
    await Future<void>.delayed(wait);
    ctrl.setCategory('lake');
    expect(repo.categories, [null, 'lake']);
  });

  test('permission denied falls back to region centre', () async {
    final c = make(FakeRepo());
    final v = await c
        .read(spotsControllerProvider.notifier)
        .resolveInitialView();
    expect(v.centre, const LatLng(49.5, 10.5));
    expect(v.zoom, 6);
  });

  test('granted location is used as the start', () async {
    final c = make(FakeRepo(), pos: const LatLng(48.1, 11.6));
    final v = await c
        .read(spotsControllerProvider.notifier)
        .resolveInitialView();
    expect(v.centre, const LatLng(48.1, 11.6));
    expect(v.located, isTrue);
  });
}
