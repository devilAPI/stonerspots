import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

const _keep = Object();

/// State of one cursor-paginated admin list.
class AdminListState<T> {
  const AdminListState({
    this.items = const [],
    this.nextCursor,
    this.q = '',
    this.status,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.loadedOnce = false,
  });

  final List<T> items;
  final String? nextCursor;

  /// Search text (users: name/email, spots: title). Empty = no filter.
  final String q;

  /// Spots only: `active`, `hidden` or null for all.
  final String? status;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final bool loadedOnce;

  bool get hasMore => nextCursor != null;

  AdminListState<T> copyWith({
    List<T>? items,
    Object? nextCursor = _keep,
    String? q,
    Object? status = _keep,
    bool? loading,
    bool? loadingMore,
    Object? error = _keep,
    bool? loadedOnce,
  }) => AdminListState<T>(
    items: items ?? this.items,
    nextCursor: identical(nextCursor, _keep)
        ? this.nextCursor
        : nextCursor as String?,
    q: q ?? this.q,
    status: identical(status, _keep) ? this.status : status as String?,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _keep) ? this.error : error,
    loadedOnce: loadedOnce ?? this.loadedOnce,
  );
}

/// Shared first-page / load-more / refresh logic of the three admin lists.
abstract class AdminListController<T> extends Notifier<AdminListState<T>> {
  int _gen = 0; // invalidates in-flight requests when the query changes

  @override
  AdminListState<T> build() => AdminListState<T>();

  AdminRepository get repo => ref.read(adminRepositoryProvider);

  Future<AdminPage<T>> fetch(String? cursor);
  int idOf(T item);

  /// First load; no-op once something was loaded.
  Future<void> load() => state.loadedOnce ? Future.value() : _first(false);

  /// Pull-to-refresh: reloads page one and replaces the list.
  Future<void> refresh() => _first(true);

  Future<void> reload() => _first(false);

  Future<void> _first(bool keepItems) async {
    final gen = ++_gen;
    state = state.copyWith(
      loading: true,
      loadingMore: false,
      error: null,
      items: keepItems ? state.items : <T>[],
      nextCursor: keepItems ? state.nextCursor : null,
    );
    try {
      final page = await fetch(null);
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
      final page = await fetch(state.nextCursor);
      if (gen != _gen) return;
      final seen = state.items.map(idOf).toSet();
      state = state.copyWith(
        items: [...state.items, ...page.items.where((i) => seen.add(idOf(i)))],
        nextCursor: page.nextCursor,
        loadingMore: false,
      );
    } catch (e) {
      if (gen != _gen) return;
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  List<T> _dedupe(List<T> items) {
    final seen = <int>{};
    return items.where((i) => seen.add(idOf(i))).toList();
  }

  void removeWhere(bool Function(T) test) {
    state = state.copyWith(items: state.items.where((i) => !test(i)).toList());
  }
}

class ReportsController extends AdminListController<AdminReport> {
  @override
  Future<AdminPage<AdminReport>> fetch(String? cursor) =>
      repo.reports(cursor: cursor);

  @override
  int idOf(AdminReport item) => item.id;

  /// Drops every report whose target belongs to [spotId].
  void removeSpot(int spotId) =>
      removeWhere((r) => r.target.exists && r.target.spotId == spotId);
}

class UsersController extends AdminListController<AdminUser> {
  @override
  Future<AdminPage<AdminUser>> fetch(String? cursor) =>
      repo.users(q: state.q.isEmpty ? null : state.q, cursor: cursor);

  @override
  int idOf(AdminUser item) => item.id;

  Future<void> search(String q) {
    state = state.copyWith(q: q.trim());
    return reload();
  }
}

class SpotsController extends AdminListController<AdminSpot> {
  @override
  Future<AdminPage<AdminSpot>> fetch(String? cursor) => repo.spots(
    q: state.q.isEmpty ? null : state.q,
    status: state.status,
    cursor: cursor,
  );

  @override
  int idOf(AdminSpot item) => item.id;

  Future<void> search(String q) {
    state = state.copyWith(q: q.trim());
    return reload();
  }

  Future<void> setStatus(String? status) {
    state = state.copyWith(status: status);
    return reload();
  }

  void removeSpot(int spotId) => removeWhere((s) => s.id == spotId);
}

final adminReportsProvider =
    NotifierProvider.autoDispose<
      ReportsController,
      AdminListState<AdminReport>
    >(ReportsController.new);

final adminUsersProvider =
    NotifierProvider.autoDispose<UsersController, AdminListState<AdminUser>>(
      UsersController.new,
    );

final adminSpotsProvider =
    NotifierProvider.autoDispose<SpotsController, AdminListState<AdminSpot>>(
      SpotsController.new,
    );

/// Deletes the spot on the server and removes it (and all reports about it)
/// from the loaded lists. A 404 means it is already gone: same result.
/// Other errors propagate and leave the lists untouched.
Future<void> removeAdminSpot(WidgetRef ref, int spotId) async {
  try {
    await ref.read(adminRepositoryProvider).deleteSpot(spotId);
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
  }
  ref.read(adminSpotsProvider.notifier).removeSpot(spotId);
  ref.read(adminReportsProvider.notifier).removeSpot(spotId);
}
