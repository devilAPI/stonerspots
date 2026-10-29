import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import 'admin_models.dart';

/// Bulk actions on users and spots, and the backend's own version and
/// updates. Kept apart from [AdminRepository]: these are actions on many
/// rows or on the server, not edits of one row.
abstract class AdminActionsRepository {
  /// `ban`, `unban` or `delete`.
  Future<BulkResult<AdminUser>> bulkUsers(List<int> ids, String action);

  /// `hide`, `show`, `lock`, `unlock`, `add_tag`, `remove_tag` (with [tag])
  /// or `delete`.
  Future<BulkResult<AdminSpot>> bulkSpots(
    List<int> ids,
    String action, {
    String? tag,
  });

  Future<SystemInfo> system();

  /// Asks the server to update itself; [channel] is `release` or `dev`.
  Future<SystemInfo> requestUpdate(String channel);
}

class ApiAdminActionsRepository implements AdminActionsRepository {
  ApiAdminActionsRepository(this._api);

  final ApiClient _api;

  @override
  Future<BulkResult<AdminUser>> bulkUsers(List<int> ids, String action) async =>
      BulkResult.fromJson(
        await _api.post<Map<String, dynamic>>(
          '/admin/users/bulk',
          data: {'ids': ids, 'action': action},
        ),
        AdminUser.fromJson,
      );

  @override
  Future<BulkResult<AdminSpot>> bulkSpots(
    List<int> ids,
    String action, {
    String? tag,
  }) async => BulkResult.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/admin/spots/bulk',
      data: {'ids': ids, 'action': action, 'tag': ?tag},
    ),
    AdminSpot.fromJson,
  );

  @override
  Future<SystemInfo> system() async => SystemInfo.fromJson(
    await _api.get<Map<String, dynamic>>('/admin/system'),
  );

  @override
  Future<SystemInfo> requestUpdate(String channel) async => SystemInfo.fromJson(
    await _api.post<Map<String, dynamic>>(
      '/admin/system/update',
      data: {'channel': channel},
    ),
  );
}

final adminActionsRepositoryProvider = Provider<AdminActionsRepository>(
  (ref) => ApiAdminActionsRepository(ref.watch(apiClientProvider)),
);

/// What a bulk action did: the changed rows as they are now, the deleted ids
/// and how many were left alone (the caller, admins, already gone).
class BulkResult<T> {
  const BulkResult({
    this.items = const [],
    this.deleted = const [],
    this.skipped = 0,
  });

  final List<T> items;
  final List<int> deleted;
  final int skipped;

  factory BulkResult.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) parse,
  ) => BulkResult(
    items: [
      for (final e in (j['items'] ?? const []) as List)
        parse(e as Map<String, dynamic>),
    ],
    deleted: [for (final e in (j['deleted'] ?? const []) as List) e as int],
    skipped: ((j['skipped'] ?? const []) as List).length,
  );
}

enum UpdateState { idle, pending, running, done, failed }

/// The last (or current) backend update the admin page asked for.
class UpdateStatus {
  const UpdateStatus({
    this.state = UpdateState.idle,
    this.channel = '',
    this.from = '',
    this.to = '',
    this.finishedAt,
    this.log = '',
  });

  final UpdateState state;
  final String channel;
  final String from;
  final String to;
  final DateTime? finishedAt;
  final String log;

  bool get busy => state == UpdateState.pending || state == UpdateState.running;

  factory UpdateStatus.fromJson(Map<String, dynamic> j) => UpdateStatus(
    state: UpdateState.values.asNameMap()[j['state']] ?? UpdateState.idle,
    channel: (j['channel'] ?? '') as String,
    from: (j['from'] ?? '') as String,
    to: (j['to'] ?? '') as String,
    finishedAt: DateTime.tryParse((j['finished_at'] ?? '') as String),
    log: (j['log'] ?? '') as String,
  );
}

class SystemInfo {
  const SystemInfo({
    this.version = '',
    this.updatesEnabled = false,
    this.update = const UpdateStatus(),
  });

  /// Installed release tag, e.g. `dev-42`; empty when unknown.
  final String version;
  final bool updatesEnabled;
  final UpdateStatus update;

  factory SystemInfo.fromJson(Map<String, dynamic> j) => SystemInfo(
    version: (j['version'] ?? '') as String,
    updatesEnabled: (j['updates_enabled'] ?? false) as bool,
    update: UpdateStatus.fromJson(
      (j['update'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    ),
  );
}
