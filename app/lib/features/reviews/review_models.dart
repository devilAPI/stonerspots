import '../../core/models.dart';

class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    required this.author,
  });

  final int id;
  final int rating;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Author author;

  /// True when the review was changed after it was written.
  bool get isEdited => updatedAt.isAfter(createdAt);

  factory Review.fromJson(Map<String, dynamic> j) => Review(
    id: j['id'] as int,
    rating: j['rating'] as int,
    body: (j['body'] ?? '') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    updatedAt: DateTime.parse((j['updated_at'] ?? j['created_at']) as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
  );
}

class ReviewSummary {
  const ReviewSummary({
    required this.avg,
    required this.count,
    required this.distribution,
  });

  static const empty = ReviewSummary(
    avg: 0,
    count: 0,
    distribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
  );

  final double avg;
  final int count;

  /// Number of reviews per star value; always has keys 1..5.
  final Map<int, int> distribution;

  factory ReviewSummary.fromJson(Map<String, dynamic> j) {
    final raw = (j['distribution'] ?? const {}) as Map;
    return ReviewSummary(
      avg: ((j['avg'] ?? 0) as num).toDouble(),
      count: (j['count'] ?? 0) as int,
      distribution: {
        for (var i = 1; i <= 5; i++) i: (raw['$i'] ?? raw[i] ?? 0) as int,
      },
    );
  }
}

class ReviewsPage {
  const ReviewsPage({
    required this.summary,
    this.mine,
    required this.items,
    this.nextCursor,
  });

  final ReviewSummary summary;

  /// The logged-in user's own review, if any.
  final Review? mine;
  final List<Review> items;
  final String? nextCursor;

  factory ReviewsPage.fromJson(Map<String, dynamic> j) => ReviewsPage(
    summary: ReviewSummary.fromJson(
      (j['summary'] ?? const <String, dynamic>{}) as Map<String, dynamic>,
    ),
    mine: j['mine'] == null
        ? null
        : Review.fromJson(j['mine'] as Map<String, dynamic>),
    items: ((j['items'] ?? const []) as List)
        .map((e) => Review.fromJson(e as Map<String, dynamic>))
        .toList(),
    nextCursor: j['next_cursor'] as String?,
  );
}
