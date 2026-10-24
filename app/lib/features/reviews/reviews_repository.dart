import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import 'review_models.dart';

abstract class ReviewsRepository {
  Future<ReviewsPage> list(int spotId, {String? cursor});

  /// Creates or replaces the current user's review.
  Future<Review> save(int spotId, int rating, String body);

  /// Deletes the current user's review; an already gone review is fine.
  Future<void> delete(int spotId);
}

class ApiReviewsRepository implements ReviewsRepository {
  ApiReviewsRepository(this._api);

  final ApiClient _api;

  @override
  Future<ReviewsPage> list(int spotId, {String? cursor}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/spots/$spotId/reviews',
      query: {'limit': 20, 'cursor': ?cursor},
    );
    return ReviewsPage.fromJson(json);
  }

  @override
  Future<Review> save(int spotId, int rating, String body) async {
    final json = await _api.put<Map<String, dynamic>>(
      '/spots/$spotId/review',
      data: {'rating': rating, 'body': body},
    );
    return Review.fromJson(json);
  }

  @override
  Future<void> delete(int spotId) async {
    try {
      await _api.delete<dynamic>('/spots/$spotId/review');
    } on ApiException catch (e) {
      if (e.status == 404 && e.code == 'not_found') return;
      rethrow;
    }
  }
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>(
  (ref) => ApiReviewsRepository(ref.watch(apiClientProvider)),
);
