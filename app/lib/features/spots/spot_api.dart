import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart' show apiClientProvider;

class SpotDraft {
  const SpotDraft({
    required this.title,
    required this.description,
    required this.category,
    required this.lat,
    required this.lon,
    this.photoIds = const [],
    this.tags = const [],
  });

  final String title;
  final String description;
  final String category;
  final double lat;
  final double lon;

  /// Already-uploaded photos; the backend turns description + photos into the
  /// spot's first update.
  final List<int> photoIds;

  /// Sent only when non-empty.
  final List<SpotTag> tags;
}

class LikeResult {
  const LikeResult({required this.liked, required this.likeCount});

  final bool liked;
  final int likeCount;
}

/// Single-spot endpoints (detail, create, like, report). The map list lives in
/// Task 8's SpotsRepository.
abstract class SpotApi {
  Future<Spot> getSpot(int id);

  /// Throws [ApiException] with code `possible_duplicate` (409) unless [force].
  Future<Spot> createSpot(SpotDraft draft, {bool force = false});
  Future<LikeResult> setLike(int spotId, {required bool liked});

  /// Replaces the tags of a spot (author or admin); returns the full spot.
  Future<Spot> setTags(int id, List<SpotTag> tags);

  /// [targetType] is `spot` or `update`.
  Future<void> report(String targetType, int targetId, String reason);
}

class ApiSpotApi implements SpotApi {
  ApiSpotApi(this._api);

  final ApiClient _api;

  @override
  Future<Spot> getSpot(int id) async =>
      Spot.fromJson(await _api.get<Map<String, dynamic>>('/spots/$id'));

  @override
  Future<Spot> createSpot(SpotDraft d, {bool force = false}) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/spots',
      data: {
        'title': d.title,
        'description': d.description,
        'category': d.category,
        'lat': d.lat,
        'lon': d.lon,
        if (d.photoIds.isNotEmpty) 'photo_ids': d.photoIds,
        if (d.tags.isNotEmpty)
          'tags': [for (final t in SpotTag.sorted(d.tags)) t.wire],
        if (force) 'force': true,
      },
    );
    return Spot.fromJson(json);
  }

  @override
  Future<Spot> setTags(int id, List<SpotTag> tags) async => Spot.fromJson(
    await _api.put<Map<String, dynamic>>(
      '/spots/$id/tags',
      data: {
        'tags': [for (final t in SpotTag.sorted(tags)) t.wire],
      },
    ),
  );

  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) async {
    final path = '/spots/$spotId/like';
    final json = liked
        ? await _api.put<Map<String, dynamic>>(path)
        : await _api.delete<Map<String, dynamic>>(path);
    return LikeResult(
      liked: json['liked'] as bool,
      likeCount: json['like_count'] as int,
    );
  }

  @override
  Future<void> report(String targetType, int targetId, String reason) async {
    await _api.post<dynamic>(
      '/reports',
      data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
      },
    );
  }
}

final spotApiProvider = Provider<SpotApi>(
  (ref) => ApiSpotApi(ref.watch(apiClientProvider)),
);
