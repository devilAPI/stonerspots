import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart' show apiClientProvider;

abstract class UpdatesRepository {
  /// Newest first. Uses `GET /feed?sort=new&spot_id=` (the backend must
  /// support the `spot_id` filter).
  Future<List<FeedItem>> listForSpot(int spotId);

  Future<void> post(
    int spotId, {
    required String body,
    List<int> photoIds,
    UpdateTag tag,
  });

  /// `PATCH /updates/{id}`; only the given fields are sent.
  Future<void> edit(int id, {String? body, UpdateTag? tag});

  /// `DELETE /updates/{id}`.
  Future<void> delete(int id);
}

class ApiUpdatesRepository implements UpdatesRepository {
  ApiUpdatesRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<FeedItem>> listForSpot(int spotId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/feed',
      query: {'sort': 'new', 'spot_id': spotId, 'limit': 50},
    );
    return ((json['items'] ?? const []) as List)
        .map((e) => FeedItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> post(
    int spotId, {
    required String body,
    List<int> photoIds = const [],
    UpdateTag tag = UpdateTag.note,
  }) async {
    await _api.post<dynamic>(
      '/spots/$spotId/updates',
      data: {'body': body, 'photo_ids': photoIds, 'tag': tag.wire},
    );
  }

  @override
  Future<void> edit(int id, {String? body, UpdateTag? tag}) async {
    await _api.patch<dynamic>(
      '/updates/$id',
      data: {'body': ?body, 'tag': ?tag?.wire},
    );
  }

  @override
  Future<void> delete(int id) async {
    await _api.delete<dynamic>('/updates/$id');
  }
}

/// Named differently from the placeholder `updatesRepositoryProvider` in
/// core/providers.dart so both can coexist until integration removes it.
final spotUpdatesRepositoryProvider = Provider<UpdatesRepository>(
  (ref) => ApiUpdatesRepository(ref.watch(apiClientProvider)),
);
