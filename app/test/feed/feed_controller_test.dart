import 'package:app/core/models.dart';
import 'package:app/features/feed/feed_controller.dart';
import 'package:app/core/location_service.dart';
import 'package:app/core/settings.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem item(int id) => FeedItem(
  id: id,
  body: 'b$id',
  photos: const [],
  createdAt: DateTime(2026, 1, 1),
  author: const Author(id: 1, displayName: 'a'),
  spot: const Spot(id: 1, title: 's', lat: 0, lon: 0),
);

class Call {
  Call(
    this.sort,
    this.lat,
    this.lon,
    this.cursor, [
    this.tags = const [],
    this.following = false,
    this.radiusKm,
  ]);
  final int? radiusKm;
  final List<SpotTag> tags;
  final bool following;
  final FeedSort sort;
  final double? lat, lon;
  final String? cursor;
}

class FakeRepo implements FeedRepository {
  final calls = <Call>[];
  FeedPage Function(Call c) handler = (_) => const FeedPage([], null);

  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
    List<SpotTag> tags = const [],
    bool following = false,
    int? radiusKm,
  }) async {
    final c = Call(sort, lat, lon, cursor, tags, following, radiusKm);
    calls.add(c);
    return handler(c);
  }
}

class FakeLocation implements LocationService {
  FakeLocation(this.result);
  final LatLng? result;
  @override
  Future<LatLng?> currentPosition() async => result;
}

ProviderContainer make(FakeRepo repo, {LatLng? loc, SettingsStore? store}) {
  final c = ProviderContainer(
    overrides: [
      feedRepositoryProvider.overrideWithValue(repo),
      locationServiceProvider.overrideWithValue(FakeLocation(loc)),
      if (store != null) settingsStoreProvider.overrideWithValue(store),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('changing sort resets pagination', () async {
    final repo = FakeRepo()
      ..handler = (c) => c.cursor == null
          ? FeedPage([item(1), item(2)], 'c1')
          : FeedPage([item(3)], null);
    final c = make(repo);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    await n.loadMore();
    expect(c.read(feedControllerProvider).items.map((i) => i.id), [1, 2, 3]);

    await n.setSort(FeedSort.top);
    final s = c.read(feedControllerProvider);
    expect(s.sort, FeedSort.top);
    expect(repo.calls.last.cursor, isNull);
    expect(repo.calls.last.sort, FeedSort.top);
    expect(s.items.map((i) => i.id), [1, 2]);
    expect(s.nextCursor, 'c1');

    expect(repo.calls.last.cursor, isNull);
    expect(repo.calls.last.sort, FeedSort.top);
  });

  test('loads next page when near end and stops at null cursor', () async {
    final repo = FakeRepo()
      ..handler = (c) => switch (c.cursor) {
        null => FeedPage([item(1)], 'c1'),
        'c1' => FeedPage([item(2)], null),
        _ => throw StateError('unexpected'),
      };
    final c = make(repo);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    await n.loadMore();
    expect(c.read(feedControllerProvider).hasMore, isFalse);
    final before = repo.calls.length;
    await n.loadMore();
    expect(repo.calls.length, before);
    expect(c.read(feedControllerProvider).items.length, 2);
  });

  test('nearby falls back to new when location denied', () async {
    final repo = FakeRepo();
    final c = make(repo, loc: null);
    final n = c.read(feedControllerProvider.notifier);
    await n.setSort(FeedSort.nearby);
    final s = c.read(feedControllerProvider);
    expect(s.sort, FeedSort.newest);
    expect(s.locationDenied, isTrue);
    expect(repo.calls.last.sort, FeedSort.newest);
    expect(repo.calls.last.lat, isNull);
  });

  test('nearby passes coordinates when location granted', () async {
    final repo = FakeRepo();
    final c = make(repo, loc: const LatLng(1.5, 2.5));
    await c.read(feedControllerProvider.notifier).setSort(FeedSort.nearby);
    expect(c.read(feedControllerProvider).sort, FeedSort.nearby);
    expect(repo.calls.last.lat, 1.5);
    expect(repo.calls.last.lon, 2.5);
  });

  test('no duplicate items after refresh', () async {
    var round = 0;
    final repo = FakeRepo()
      ..handler = (c) {
        if (c.cursor != null) return FeedPage([item(2), item(3)], null);
        round++;
        return round == 1
            ? FeedPage([item(1), item(2)], 'c1')
            : FeedPage([item(0), item(1), item(2)], 'c1');
      };
    final c = make(repo);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    await n.loadMore();
    await n.refresh();
    expect(c.read(feedControllerProvider).items.map((i) => i.id), [0, 1, 2]);
    await n.loadMore();
    final ids = c.read(feedControllerProvider).items.map((i) => i.id).toList();
    expect(ids, [0, 1, 2, 3]);
  });

  test('tags are passed and a change resets pagination', () async {
    final repo = FakeRepo()
      ..handler = (c) => c.cursor == null
          ? FeedPage([item(1), item(2)], 'c1')
          : FeedPage([item(3)], null);
    final c = make(repo);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    expect(repo.calls.last.tags, isEmpty);
    await n.loadMore();
    expect(c.read(feedControllerProvider).items, hasLength(3));

    await n.toggleTag(SpotTag.quiet);
    await n.toggleTag(SpotTag.roof);
    expect(repo.calls.last.tags, [SpotTag.roof, SpotTag.quiet]);
    expect(repo.calls.last.cursor, isNull);
    expect(c.read(feedControllerProvider).items, hasLength(2));

    await n.loadMore();
    expect(repo.calls.last.cursor, 'c1');
    expect(repo.calls.last.tags, [SpotTag.roof, SpotTag.quiet]);

    await n.toggleTag(SpotTag.roof);
    expect(repo.calls.last.tags, [SpotTag.quiet]);
    await n.clearTags();
    expect(repo.calls.last.tags, isEmpty);
    expect(repo.calls.last.cursor, isNull);
  });

  test('following filter is passed, kept while paging, and resets', () async {
    final repo = FakeRepo()
      ..handler = (c) => c.cursor == null
          ? FeedPage([item(1), item(2)], 'c1')
          : FeedPage([item(3)], null);
    final c = make(repo);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    expect(repo.calls.last.following, isFalse);
    await n.loadMore();

    await n.setFollowing(true);
    expect(c.read(feedControllerProvider).following, isTrue);
    expect(repo.calls.last.following, isTrue);
    expect(repo.calls.last.cursor, isNull);
    expect(c.read(feedControllerProvider).items, hasLength(2));
    await n.loadMore();
    expect(repo.calls.last.following, isTrue);
    expect(repo.calls.last.cursor, 'c1');

    // sort and tags combine with it
    await n.setSort(FeedSort.top);
    expect(repo.calls.last.following, isTrue);
    expect(repo.calls.last.sort, FeedSort.top);

    final before = repo.calls.length;
    await n.setFollowing(true); // no change, no reload
    expect(repo.calls, hasLength(before));

    await n.setFollowing(false);
    expect(repo.calls.last.following, isFalse);
    expect(c.read(feedControllerProvider).following, isFalse);
  });

  test('a radius filters around the position, with every sort', () async {
    final repo = FakeRepo();
    final store = SettingsStore.memory();
    final c = make(repo, loc: const LatLng(48.1, 11.6), store: store);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    expect(repo.calls.last.radiusKm, isNull);
    expect(repo.calls.last.lat, isNull);

    await n.setRadius(25);
    expect(c.read(feedControllerProvider).radiusKm, 25);
    expect(c.read(feedControllerProvider).filterCount, 1);
    expect(repo.calls.last.sort, FeedSort.newest);
    expect(repo.calls.last.radiusKm, 25);
    expect(repo.calls.last.lat, 48.1);
    expect(repo.calls.last.lon, 11.6);
    expect(store.getInt(FeedController.radiusKey), 25);

    await n.setSort(FeedSort.top);
    expect(repo.calls.last.radiusKm, 25);
    expect(repo.calls.last.lat, 48.1);

    await n.setRadius(null);
    expect(repo.calls.last.radiusKm, isNull);
    expect(repo.calls.last.lat, isNull);
    expect(store.getInt(FeedController.radiusKey), isNull);
  });

  test('no radius without a position', () async {
    final repo = FakeRepo();
    final c = make(repo, loc: null);
    final n = c.read(feedControllerProvider.notifier);
    await n.load();
    final before = repo.calls.length;
    await n.setRadius(10);
    final s = c.read(feedControllerProvider);
    expect(s.radiusKm, isNull);
    expect(s.locationDenied, isTrue);
    expect(repo.calls.length, before);
  });

  test('the radius is kept for next time', () async {
    final store = SettingsStore.memory();
    await store.setInt(FeedController.radiusKey, 50);
    final repo = FakeRepo();
    final c = make(repo, loc: const LatLng(1, 2), store: store);
    await c.read(feedControllerProvider.notifier).load();
    expect(c.read(feedControllerProvider).radiusKm, 50);
    expect(repo.calls.last.radiusKm, 50);
    expect(repo.calls.last.lat, 1);

    // without a position now: anywhere, but the setting stays
    final repo2 = FakeRepo();
    final c2 = make(repo2, loc: null, store: store);
    await c2.read(feedControllerProvider.notifier).load();
    expect(c2.read(feedControllerProvider).radiusKm, isNull);
    expect(repo2.calls.last.radiusKm, isNull);
    expect(store.getInt(FeedController.radiusKey), 50);
  });

  test('reset turns every filter off, the sort stays', () async {
    final repo = FakeRepo();
    final c = make(repo, loc: const LatLng(1, 2));
    final n = c.read(feedControllerProvider.notifier);
    await n.setSort(FeedSort.top);
    await n.setRadius(5);
    await n.toggleTag(SpotTag.roof);
    await n.setFollowing(true);
    expect(c.read(feedControllerProvider).filterCount, 3);
    await n.clearFilters();
    final s = c.read(feedControllerProvider);
    expect(s.filterCount, 0);
    expect(s.sort, FeedSort.top);
    expect(repo.calls.last.radiusKm, isNull);
    expect(repo.calls.last.tags, isEmpty);
    expect(repo.calls.last.following, isFalse);
  });
}
