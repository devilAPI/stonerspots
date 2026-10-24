import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:latlong2/latlong.dart';

import '../../core/location_service.dart';
import '../../core/models.dart';
import 'feed_repository.dart';

class FeedState {
  const FeedState({
    this.items = const [],
    this.nextCursor,
    this.sort = FeedSort.newest,
    this.category,
    this.tags = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.locationDenied = false,
    this.loadedOnce = false,
  });

  final List<FeedItem> items;
  final String? nextCursor;
  final FeedSort sort;
  final String? category;

  /// Selected tag filters (all must match), canonical order.
  final List<SpotTag> tags;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final bool locationDenied;
  final bool loadedOnce;

  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<FeedItem>? items,
    Object? nextCursor = _keep,
    FeedSort? sort,
    Object? category = _keep,
    List<SpotTag>? tags,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    bool? locationDenied,
    bool? loadedOnce,
  }) => FeedState(
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    sort: sort ?? this.sort,
    category: identical(category, _keep) ? this.category : category as String?,
    tags: tags ?? this.tags,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _keep) ? this.error : error,
    locationDenied: locationDenied ?? this.locationDenied,
    loadedOnce: loadedOnce ?? this.loadedOnce,
  );
}

const _keep = Object();

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

class FeedController extends Notifier<FeedState> {
  LatLng? _pos;
  int _gen = 0; // invalidates in-flight requests when the query changes

  @override
  FeedState build() => const FeedState();

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  /// Loads the first page for the current sort/category.
  Future<void> load() => _loadFirst(keepItems: false);

  /// Pull-to-refresh: reloads page one and replaces the list (no duplicates).
  Future<void> refresh() => _loadFirst(keepItems: true);

  Future<void> setSort(FeedSort sort) async {
    var effective = sort;
    var denied = false;
    if (sort == FeedSort.nearby) {
      _pos = await ref.read(locationServiceProvider).currentPosition();
      if (_pos == null) {
        effective = FeedSort.newest;
        denied = true;
      }
    }
    state = state.copyWith(sort: effective, locationDenied: denied);
    await _loadFirst(keepItems: false);
  }

  Future<void> setCategory(String? category) async {
    state = state.copyWith(category: category);
    await _loadFirst(keepItems: false);
  }

  Future<void> toggleTag(SpotTag tag) async {
    final next = state.tags.contains(tag)
        ? state.tags.where((t) => t != tag)
        : [...state.tags, tag];
    state = state.copyWith(tags: SpotTag.sorted(next));
    await _loadFirst(keepItems: false);
  }

  Future<void> clearTags() async {
    state = state.copyWith(tags: const []);
    await _loadFirst(keepItems: false);
  }

  Future<void> _loadFirst({required bool keepItems}) async {
    final gen = ++_gen;
    state = state.copyWith(
      loading: true,
      loadingMore: false,
      error: null,
      items: keepItems ? state.items : const [],
      nextCursor: keepItems ? state.nextCursor : null,
    );
    try {
      final page = await _fetch(null);
      if (gen != _gen) return;
      state = state.copyWith(
        items: _dedupe(page.items),
        nextCursor: page.nextCursor,
        loading: false,
        loadedOnce: true,
      );
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(loading: false, error: e, loadedOnce: true);
    }
  }

  /// Appends the next page; no-op when there is none or one is in flight.
  Future<void> loadMore() async {
    if (!state.hasMore || state.loading || state.loadingMore) return;
    final gen = _gen;
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final page = await _fetch(state.nextCursor);
      if (gen != _gen) return;
      final seen = state.items.map((i) => i.id).toSet();
      state = state.copyWith(
        items: [...state.items, ...page.items.where((i) => seen.add(i.id))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  Future<FeedPage> _fetch(String? cursor) => _repo.fetch(
    sort: state.sort,
    category: state.category,
    tags: state.tags,
    lat: state.sort == FeedSort.nearby ? _pos?.latitude : null,
    lon: state.sort == FeedSort.nearby ? _pos?.longitude : null,
    cursor: cursor,
  );

  List<FeedItem> _dedupe(List<FeedItem> items) {
    final seen = <int>{};
    return items.where((i) => seen.add(i.id)).toList();
  }
}
