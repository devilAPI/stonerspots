import 'package:app/core/models.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/reviews/reviews_repository.dart';

Review review(
  int id, {
  int rating = 4,
  String body = 'nice',
  int authorId = 9,
  String name = 'Bo',
  DateTime? updated,
}) => Review(
  id: id,
  rating: rating,
  body: body,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: updated ?? DateTime(2026, 10, 1),
  author: Author(id: authorId, displayName: name),
);

ReviewSummary summaryOf(Map<int, int> d) {
  final full = {for (var i = 1; i <= 5; i++) i: d[i] ?? 0};
  final count = full.values.fold<int>(0, (a, b) => a + b);
  final sum = full.entries.fold<int>(0, (a, e) => a + e.key * e.value);
  return ReviewSummary(
    avg: count == 0 ? 0 : sum / count,
    count: count,
    distribution: full,
  );
}

class FakeReviews implements ReviewsRepository {
  /// [pages] are returned in order by first-page loads (the last repeats);
  /// [more] answers loads with a cursor.
  FakeReviews(this.pages, {this.more});

  final List<ReviewsPage> pages;
  final ReviewsPage? more;
  final calls = <String>[];
  Object? saveError;
  int _firstLoads = 0;

  @override
  Future<ReviewsPage> list(int spotId, {String? cursor}) async {
    calls.add('list:${cursor ?? ''}');
    if (cursor != null) return more!;
    final i = _firstLoads < pages.length ? _firstLoads : pages.length - 1;
    _firstLoads++;
    return pages[i];
  }

  @override
  Future<Review> save(int spotId, int rating, String body) async {
    calls.add('save:$rating:$body');
    if (saveError != null) throw saveError!;
    return review(99, rating: rating, body: body, authorId: 1, name: 'Me');
  }

  @override
  Future<void> delete(int spotId) async {
    calls.add('delete');
  }
}
