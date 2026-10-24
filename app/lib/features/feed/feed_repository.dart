import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart' show apiClientProvider;

enum FeedSort {
  newest('new'),
  top('top'),
  nearby('nearby');

  const FeedSort(this.apiValue);
  final String apiValue;
}

class FeedPage {
  const FeedPage(this.items, this.nextCursor);
  final List<FeedItem> items;
  final String? nextCursor;
}

abstract class FeedRepository {
  Future<FeedPage> fetch({
    required FeedSort sort,
    String? category,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
  });
}

class ApiFeedRepository implements FeedRepository {
  ApiFeedRepository(this._api);
  final ApiClient _api;

  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    String? category,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/feed',
      query: {
        'sort': sort.apiValue,
        'category': ?category,
        'lat': ?lat,
        'lon': ?lon,
        'cursor': ?cursor,
        'limit': limit,
      },
    );
    return FeedPage(
      ((json['items'] ?? const []) as List)
          .map((e) => FeedItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['next_cursor'] as String?,
    );
  }
}

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => ApiFeedRepository(ref.watch(apiClientProvider)),
);
