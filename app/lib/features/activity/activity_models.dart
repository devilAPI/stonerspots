import '../../core/models.dart' show Author;

/// What happened.
enum ActivityKind {
  follow('follow'),
  comment('comment'),
  like('like'),
  review('review');

  const ActivityKind(this.wire);
  final String wire;

  /// Null for a kind this app does not know yet.
  static ActivityKind? parse(String? s) {
    for (final k in values) {
      if (k.wire == s) return k;
    }
    return null;
  }
}

/// The spot an activity item is about.
class ActivitySpot {
  const ActivitySpot({required this.id, required this.title});

  final int id;
  final String title;

  factory ActivitySpot.fromJson(Map<String, dynamic> j) =>
      ActivitySpot(id: j['id'] as int, title: (j['title'] ?? '') as String);
}

/// One item of `GET /me/activity`: someone did something to your content.
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.actor,
    this.read = false,
    this.spot,
    this.updateId,
    this.commentPreview,
  });

  final int id;
  final ActivityKind kind;
  final DateTime createdAt;
  final Author actor;
  final bool read;
  final ActivitySpot? spot;
  final int? updateId;

  /// The start of the comment (kind comment only).
  final String? commentPreview;

  /// Where tapping the item goes: the actor for a follow, the spot otherwise.
  String get target => kind == ActivityKind.follow || spot == null
      ? '/user/${actor.id}'
      : '/spot/${spot!.id}';

  /// Null for a kind this app does not know yet.
  static ActivityItem? fromJson(Map<String, dynamic> j) {
    final kind = ActivityKind.parse(j['kind'] as String?);
    if (kind == null) return null;
    final spot = j['spot'];
    return ActivityItem(
      id: j['id'] as int,
      kind: kind,
      createdAt: DateTime.parse(j['created_at'] as String),
      actor: Author.fromJson(j['actor'] as Map<String, dynamic>),
      read: (j['read'] ?? false) as bool,
      spot: spot is Map<String, dynamic> ? ActivitySpot.fromJson(spot) : null,
      updateId: j['update_id'] as int?,
      commentPreview: j['comment_preview'] as String?,
    );
  }
}
