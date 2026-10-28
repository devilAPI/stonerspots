import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import 'feed_repository.dart';

class FeedState {
  const FeedState({
    this.page = const Paged(),
    this.sort = FeedSort.newest,
    this.tags = const [],
    this.locationDenied = false,
  });

  final Paged<FeedItem> page;
  final FeedSort sort;

  /// Selected tag filters (all must match), canonical order.
  final List<SpotTag> tags;
  final bool locationDenied;

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
  }) => FeedState(
    page: page ?? this.page,
    sort: sort ?? this.sort,
    tags: tags ?? this.tags,
    locationDenied: locationDenied ?? this.locationDenied,
  );
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

class FeedController extends Notifier<FeedState>
    with CursorPaging<FeedState, FeedItem> {
  LatLng? _pos;

  @override
  FeedState build() => const FeedState();

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  /// Loads the first page for the current sort/tags.
  Future<void> load() => loadFirst();

  /// Pull-to-refresh: reloads page one and replaces the list (no duplicates).
  Future<void> refresh() => loadFirst(keepItems: true);

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
    await loadFirst();
  }

  Future<void> toggleTag(SpotTag tag) async {
    final next = state.tags.contains(tag)
        ? state.tags.where((t) => t != tag)
        : [...state.tags, tag];
    state = state.copyWith(tags: SpotTag.sorted(next));
    await loadFirst();
  }

  Future<void> clearTags() async {
    state = state.copyWith(tags: const []);
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
    lat: state.sort == FeedSort.nearby ? _pos?.latitude : null,
    lon: state.sort == FeedSort.nearby ? _pos?.longitude : null,
    cursor: cursor,
  );
}
