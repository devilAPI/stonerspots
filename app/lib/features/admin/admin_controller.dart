import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/paging.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

const _keep = Object();

/// State of one cursor-paginated admin list.
class AdminListState<T> {
  // Not const: a const default could not name T (it would be Paged<Never>).
  AdminListState({Paged<T>? page, this.q = '', this.status})
    : page = page ?? Paged<T>();

  final Paged<T> page;

  /// Search text (users: name/email, spots: title). Empty = no filter.
  final String q;

  /// Spots only: `active`, `hidden` or null for all.
  final String? status;

  List<T> get items => page.items;
  bool get loading => page.loading;
  bool get loadingMore => page.loadingMore;
  Object? get error => page.error;
  bool get loadedOnce => page.loadedOnce;
  String? get nextCursor => page.nextCursor;
  bool get hasMore => page.hasMore;

  AdminListState<T> copyWith({
    Paged<T>? page,
    List<T>? items,
    String? q,
    Object? status = _keep,
  }) => AdminListState<T>(
    page: items == null
        ? page ?? this.page
        : (page ?? this.page).copyWith(items: items),
    q: q ?? this.q,
    status: identical(status, _keep) ? this.status : status as String?,
  );
}

/// The three admin lists: paging plus a few list edits.
abstract class AdminListController<T> extends Notifier<AdminListState<T>>
    with CursorPaging<AdminListState<T>, T> {
  @override
  AdminListState<T> build() => AdminListState<T>();

  AdminRepository get repo => ref.read(adminRepositoryProvider);

  @override
  Paged<T> get paged => state.page;

  @override
  set paged(Paged<T> value) => state = state.copyWith(page: value);

  /// First load; no-op once something was loaded.
  Future<void> load() => state.loadedOnce ? Future.value() : loadFirst();

  /// Pull-to-refresh: reloads page one and replaces the list.
  Future<void> refresh() => loadFirst(keepItems: true);

  Future<void> reload() => loadFirst();

  void removeWhere(bool Function(T) test) {
    state = state.copyWith(items: state.items.where((i) => !test(i)).toList());
  }
}

class ReportsController extends AdminListController<AdminReport> {
  @override
  Future<AdminPage<AdminReport>> fetchPage(String? cursor) =>
      repo.reports(cursor: cursor);

  @override
  int idOf(AdminReport item) => item.id;

  /// Drops every report whose target belongs to [spotId].
  void removeSpot(int spotId) =>
      removeWhere((r) => r.target.exists && r.target.spotId == spotId);

  /// Drops every report about the review/update [targetId].
  void removeTarget(String targetType, int targetId) =>
      removeWhere((r) => r.targetType == targetType && r.targetId == targetId);

  /// Mirrors an edited spot into the report tiles that show it.
  void applySpot(AdminSpot spot) => _map(
    (r) => r.target.exists && r.target.spotId == spot.id
        ? r.copyWith(
            target: r.target.copyWith(title: spot.title, status: spot.status),
          )
        : r,
  );

  /// Removes one report and lowers the count shown on the remaining reports
  /// of the same target.
  void dismissOne(AdminReport report) {
    final items = <AdminReport>[];
    for (final r in state.items) {
      if (r.id == report.id) continue;
      items.add(
        _sameTarget(r, report)
            ? r.copyWith(reportCount: _dec(r.reportCount, 1))
            : r,
      );
    }
    state = state.copyWith(items: items);
  }

  /// Removes every loaded report of [report]'s target.
  void dismissTarget(AdminReport report) =>
      removeWhere((r) => _sameTarget(r, report));

  static bool _sameTarget(AdminReport a, AdminReport b) =>
      a.targetType == b.targetType && a.targetId == b.targetId;

  void _map(AdminReport Function(AdminReport) f) {
    state = state.copyWith(items: state.items.map(f).toList());
  }
}

int _dec(int n, int by) => n - by < 0 ? 0 : n - by;

class UsersController extends AdminListController<AdminUser> {
  @override
  Future<AdminPage<AdminUser>> fetchPage(String? cursor) =>
      repo.users(q: state.q.isEmpty ? null : state.q, cursor: cursor);

  @override
  int idOf(AdminUser item) => item.id;

  Future<void> search(String q) {
    state = state.copyWith(q: q.trim());
    return reload();
  }

  void replace(AdminUser user) => state = state.copyWith(
    items: [for (final u in state.items) u.id == user.id ? user : u],
  );
}

class SpotsController extends AdminListController<AdminSpot> {
  @override
  Future<AdminPage<AdminSpot>> fetchPage(String? cursor) => repo.spots(
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

  void replace(AdminSpot spot) => state = state.copyWith(
    items: [for (final s in state.items) s.id == spot.id ? spot : s],
  );

  /// After dismissing reports on a spot: lower its report count by [removed]
  /// and, with [restore], show it as active again.
  void reportsDismissed(int spotId, int removed, {required bool restore}) =>
      state = state.copyWith(
        items: [
          for (final s in state.items)
            s.id == spotId
                ? s.copyWith(
                    reportCount: _dec(s.reportCount, removed),
                    status: restore ? 'active' : null,
                  )
                : s,
        ],
      );
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

/// Mirrors an edited spot the result into every loaded list.
void applyEditedSpot(WidgetRef ref, AdminSpot spot) {
  ref.read(adminSpotsProvider.notifier).replace(spot);
  ref.read(adminReportsProvider.notifier).applySpot(spot);
}

/// Dismisses one report; 404 counts as already removed. Other errors
/// propagate and leave the list untouched.
Future<void> dismissAdminReport(WidgetRef ref, AdminReport report) async {
  try {
    await ref.read(adminRepositoryProvider).deleteReport(report.id);
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
  }
  ref.read(adminReportsProvider.notifier).dismissOne(report);
  if (report.targetType == 'spot' && report.target.spotId != null) {
    ref
        .read(adminSpotsProvider.notifier)
        .reportsDismissed(report.target.spotId!, 1, restore: false);
  }
}

/// Dismisses all reports of the target; returns how many the server removed.
Future<int> dismissAdminReportsOfTarget(
  WidgetRef ref,
  AdminReport report, {
  required bool restore,
}) async {
  final removed = await ref
      .read(adminRepositoryProvider)
      .dismissReports(
        targetType: report.targetType,
        targetId: report.targetId,
        restore: restore,
      );
  ref.read(adminReportsProvider.notifier).dismissTarget(report);
  if (report.targetType == 'spot' && report.target.spotId != null) {
    ref
        .read(adminSpotsProvider.notifier)
        .reportsDismissed(report.target.spotId!, removed, restore: restore);
  }
  return removed;
}

/// Deletes the reported review or update ([report]'s target) on the server
/// and drops every report about it. A 404 means it is already gone. Other
/// errors propagate and leave the list untouched.
Future<void> removeAdminReportTarget(WidgetRef ref, AdminReport report) async {
  final repo = ref.read(adminRepositoryProvider);
  try {
    if (report.targetType == 'review') {
      await repo.deleteReview(report.targetId);
    } else {
      await repo.deleteUpdate(report.targetId);
    }
  } on ApiException catch (e) {
    if (e.status != 404) rethrow;
  }
  ref
      .read(adminReportsProvider.notifier)
      .removeTarget(report.targetType, report.targetId);
}
