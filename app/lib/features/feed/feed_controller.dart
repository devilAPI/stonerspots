import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/settings.dart';
import 'feed_repository.dart';

class FeedState {
  const FeedState({
    this.page = const Paged(),
    this.sort = FeedSort.newest,
    this.tags = const [],
    this.locationDenied = false,
    this.following = false,
    this.radiusKm,
  });

  final Paged<FeedItem> page;
  final FeedSort sort;

  /// Selected tag filters (all must match), canonical order.
  final List<SpotTag> tags;
  final bool locationDenied;

  /// Only updates of people the user follows (needs a login).
  final bool following;

  /// Only spots within this many km of the user; null: anywhere.
  final int? radiusKm;

  /// How many filters narrow the feed (the sort is not one).
  int get filterCount =>
      tags.length + (following ? 1 : 0) + (radiusKm != null ? 1 : 0);

  List<FeedItem> get items => page.items;
  bool get loading => page.loading;
  bool get loadingMore => page.loadingMore;
  Object? get error => page.error;
  bool get loadedOnce => page.loadedOnce;
  String? get nextCursor => page.nextCursor;
  bool get hasMore => page.hasMore;

  FeedState copyWith({
    Paged<FeedItem>? page,
    FeedSort? sort,
    List<SpotTag>? tags,
    bool? locationDenied,
    bool? following,
    int? Function()? radiusKm,
  }) => FeedState(
    page: page ?? this.page,
    sort: sort ?? this.sort,
    tags: tags ?? this.tags,
    locationDenied: locationDenied ?? this.locationDenied,
    following: following ?? this.following,
    radiusKm: radiusKm != null ? radiusKm() : this.radiusKm,
  );
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

class FeedController extends Notifier<FeedState>
    with CursorPaging<FeedState, FeedItem> {
  LatLng? _pos;

  /// The radius chosen last time, kept on the device.
  static const radiusKey = 'feed_radius_km';

  /// The radii the filter offers, in km.
  static const radiusSteps = [1, 2, 5, 10, 25, 50, 100, 250, 500];

  @override
  FeedState build() => FeedState(
    radiusKm: switch (ref.read(settingsStoreProvider).getInt(radiusKey)) {
      final km? when radiusSteps.contains(km) => km,
      _ => null,
    },
  );

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  bool get _needsPosition =>
      state.sort == FeedSort.nearby || state.radiusKm != null;

  /// Loads the first page for the current sort and filters.
  Future<void> load() async {
    if (_needsPosition && !await _locate()) {
      // a radius kept from last time, but no location now: anywhere, for
      // this session only (the setting stays for next time)
      state = state.copyWith(
        sort: state.sort == FeedSort.nearby ? FeedSort.newest : null,
        radiusKm: () => null,
      );
    }
    await loadFirst();
  }

  /// Pull-to-refresh: reloads page one and replaces the list (no duplicates);
  /// asks for the position again, the user may have moved.
  Future<void> refresh() async {
    if (_needsPosition) await _locate();
    await loadFirst(keepItems: true);
  }

  /// Asks for the position; false (and a note for the user) without one.
  Future<bool> _locate() async {
    state = state.copyWith(locationDenied: false);
    final pos = await ref.read(locationServiceProvider).currentPosition();
    if (pos != null) _pos = pos;
    if (_pos == null) state = state.copyWith(locationDenied: true);
    return _pos != null;
  }

  Future<void> setSort(FeedSort sort) async {
    if (sort == FeedSort.nearby && !await _locate()) {
      sort = FeedSort.newest;
    }
    state = state.copyWith(sort: sort);
    await loadFirst();
  }

  /// Only spots within [km] of the user, or anywhere with null. Without a
  /// position the radius stays as it was.
  Future<void> setRadius(int? km) async {
    if (km == state.radiusKm) return;
    if (km != null && !await _locate()) return;
    state = state.copyWith(radiusKm: () => km);
    ref.read(settingsStoreProvider).setInt(radiusKey, km);
    await loadFirst();
  }

  Future<void> toggleTag(SpotTag tag) async {
    final next = state.tags.contains(tag)
        ? state.tags.where((t) => t != tag)
        : [...state.tags, tag];
    state = state.copyWith(tags: SpotTag.sorted(next));
    await loadFirst();
  }

  /// Shows only updates of people the user follows, or everyone again.
  Future<void> setFollowing(bool following) async {
    if (state.following == following) return;
    state = state.copyWith(following: following);
    await loadFirst();
  }

  Future<void> clearTags() async {
    state = state.copyWith(tags: const []);
    await loadFirst();
  }

  /// Every filter off (the sort stays).
  Future<void> clearFilters() async {
    if (state.filterCount == 0) return;
    state = state.copyWith(
      tags: const [],
      following: false,
      radiusKm: () => null,
    );
    ref.read(settingsStoreProvider).setInt(radiusKey, null);
    await loadFirst();
  }

  @override
  Paged<FeedItem> get paged => state.page;

  @override
  set paged(Paged<FeedItem> value) => state = state.copyWith(page: value);

  @override
  int idOf(FeedItem item) => item.id;

  @override
  Future<FeedPage> fetchPage(String? cursor) => _repo.fetch(
    sort: state.sort,
    tags: state.tags,
    following: state.following,
    radiusKm: state.radiusKm,
    lat: _needsPosition ? _pos?.latitude : null,
    lon: _needsPosition ? _pos?.longitude : null,
    cursor: cursor,
  );
}
