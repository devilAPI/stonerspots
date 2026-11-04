import '../../core/models.dart' show Author;

/// The longest comment the API takes, in characters.
const kCommentMaxLength = 500;

/// A comment on a spot.
class Comment {
  const Comment({
    required this.id,
    required this.spotId,
    required this.body,
    required this.createdAt,
    required this.author,
    this.mine = false,
  });

  final int id;
  final int spotId;
  final String body;
  final DateTime createdAt;
  final Author author;

  /// The current user wrote it.
  final bool mine;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
    id: j['id'] as int,
    spotId: (j['spot_id'] ?? 0) as int,
    body: (j['body'] ?? '') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    mine: (j['mine'] ?? false) as bool,
  );
}
