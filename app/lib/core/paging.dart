import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One page of a cursor-paginated list plus the cursor for the next one
/// (null = end).
class CursorPage<T> {
  const CursorPage(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;

  factory CursorPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => CursorPage(
    ((json['items'] ?? const []) as List)
        .map((e) => parse(e as Map<String, dynamic>))
        .toList(),
    json['next_cursor'] as String?,
  );
}

const _keep = Object();

/// What a paginated list has loaded so far.
class Paged<T> {
  const Paged({
    this.items = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.loadedOnce = false,
  });

  final List<T> items;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final bool loadedOnce;

  bool get hasMore => nextCursor != null;

  Paged<T> copyWith({
    List<T>? items,
    Object? nextCursor = _keep,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    bool? loadedOnce,
  }) => Paged<T>(
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _keep) ? this.error : error,
    loadedOnce: loadedOnce ?? this.loadedOnce,
  );
}

/// First-page / load-more / refresh logic for a notifier whose state holds a
/// [Paged] list. Items are de-duplicated by [idOf]; a newer first-page load
/// makes the answers of older requests be ignored.
mixin CursorPaging<S, T> on Notifier<S> {
  int _gen = 0;

  Paged<T> get paged;
  set paged(Paged<T> value);

  Future<CursorPage<T>> fetchPage(String? cursor);
  int idOf(T item);

  /// Loads page one; with [keepItems] (pull-to-refresh) the old list stays
  /// visible until the new one replaces it.
  Future<void> loadFirst({bool keepItems = false}) async {
    final gen = ++_gen;
    paged = paged.copyWith(
      loading: true,
      loadingMore: false,
      error: null,
      items: keepItems ? paged.items : <T>[],
      nextCursor: keepItems ? paged.nextCursor : null,
    );
    try {
      final page = await fetchPage(null);
      if (gen != _gen) return;
      final seen = <int>{};
      paged = paged.copyWith(
        items: page.items.where((i) => seen.add(idOf(i))).toList(),
        nextCursor: page.nextCursor,
        loading: false,
        loadedOnce: true,
      );
    } catch (e) {
      if (gen != _gen) return;
      paged = paged.copyWith(loading: false, error: e, loadedOnce: true);
    }
  }

  /// Appends the next page; no-op when there is none or one is in flight.
  Future<void> loadMore() async {
    if (!paged.hasMore || paged.loading || paged.loadingMore) return;
    final gen = _gen;
    paged = paged.copyWith(loadingMore: true, error: null);
    try {
      final page = await fetchPage(paged.nextCursor);
      if (gen != _gen) return;
      final seen = paged.items.map(idOf).toSet();
      paged = paged.copyWith(
        items: [...paged.items, ...page.items.where((i) => seen.add(idOf(i)))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (e) {
      if (gen != _gen) return;
      paged = paged.copyWith(loadingMore: false, error: e);
    }
  }
}
