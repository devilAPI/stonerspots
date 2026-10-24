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
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => ApiAdminRepository(ref.watch(apiClientProvider)),
);
