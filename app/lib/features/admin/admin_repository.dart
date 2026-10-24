import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_models.dart';

abstract class AdminRepository {
  Future<AdminPage<AdminReport>> reports({String? cursor, int limit = 20});

  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  });

  Future<AdminPage<AdminSpot>> spots({
    String? q,
    String? status,
    String? cursor,
    int limit = 20,
  });

  /// Deletes a spot with everything attached. 404 `not_found` is thrown as
  /// [ApiException] for the caller to treat as success.
  Future<void> deleteSpot(int id);

  /// Deletes a review. 404 `not_found` is thrown as [ApiException] for the
  /// caller to treat as success.
  Future<void> deleteReview(int id);

  /// Deletes a spot update. 404 `not_found` is thrown as [ApiException] for
  /// the caller to treat as success.
  Future<void> deleteUpdate(int id);

  /// Updates the given user fields; returns the updated user.
  Future<AdminUser> updateUser(int id, AdminUserPatch patch);

  /// Updates the given spot fields; returns the updated spot.
  Future<AdminSpot> updateSpot(int id, AdminSpotPatch patch);

  /// Removes one report. 404 `not_found` is thrown as [ApiException] for the
  /// caller to treat as success.
  Future<void> deleteReport(int id);

  /// Removes all reports of one target, optionally re-activating hidden
  /// content. Returns how many reports were removed.
  Future<int> dismissReports({
    required String targetType,
    required int targetId,
    required bool restore,
  });
}

class ApiAdminRepository implements AdminRepository {
  ApiAdminRepository(this._api);

  final ApiClient _api;

  Map<String, dynamic> _query({
    String? q,
    String? status,
    String? cursor,
    required int limit,
  }) => {'limit': limit, 'q': ?q, 'status': ?status, 'cursor': ?cursor};

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async => AdminPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/admin/reports',
      query: _query(cursor: cursor, limit: limit),
    ),
    AdminReport.fromJson,
  );

  @override
  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  }) async => AdminPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/admin/users',
      query: _query(q: q, cursor: cursor, limit: limit),
    ),
    AdminUser.fromJson,
  );

  @override
  Future<AdminPage<AdminSpot>> spots({
    String? q,
    String? status,
    String? cursor,
    int limit = 20,
  }) async => AdminPage.fromJson(
    await _api.get<Map<String, dynamic>>(
      '/admin/spots',
      query: _query(q: q, status: status, cursor: cursor, limit: limit),
    ),
    AdminSpot.fromJson,
  );

  @override
  Future<void> deleteSpot(int id) async {
    await _api.delete<dynamic>('/admin/spots/$id');
  }

  @override
  Future<void> deleteReview(int id) async {
    await _api.delete<dynamic>('/admin/reviews/$id');
  }

  @override
  Future<void> deleteUpdate(int id) async {
    await _api.delete<dynamic>('/admin/updates/$id');
  }

  @override
  Future<AdminUser> updateUser(int id, AdminUserPatch patch) async =>
      AdminUser.fromJson(
        await _api.patch<Map<String, dynamic>>(
          '/admin/users/$id',
          data: patch.toJson(),
        ),
      );

  @override
  Future<AdminSpot> updateSpot(int id, AdminSpotPatch patch) async =>
      AdminSpot.fromJson(
        await _api.patch<Map<String, dynamic>>(
          '/admin/spots/$id',
          data: patch.toJson(),
        ),
      );

  @override
  Future<void> deleteReport(int id) async {
    await _api.delete<dynamic>('/admin/reports/$id');
  }

  @override
  Future<int> dismissReports({
    required String targetType,
    required int targetId,
    required bool restore,
  }) async {
    final r = await _api.post<Map<String, dynamic>>(
      '/admin/reports/dismiss',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'restore': restore,
      },
    );
    return (r['removed'] ?? 0) as int;
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
);
