double _d(Object? v) => (v as num).toDouble();

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
    this.isAdmin = false,
  });

  final int id;
  final String email;
  final String displayName;
  final bool isAdmin;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as int,
    email: (j['email'] ?? '') as String,
    displayName: (j['display_name'] ?? '') as String,
    isAdmin: (j['is_admin'] ?? false) as bool,
  );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(id, email, displayName, isAdmin);
}

class Spot {
  const Spot({
    required this.id,
    required this.title,
    this.description = '',
    required this.category,
    required this.lat,
    required this.lon,
    this.likeCount = 0,
    this.coverUrl,
    this.distanceM,
    this.ratingAvg = 0,
    this.ratingCount = 0,
  });

  final int id;
  final String title;
  final String description;
  final String category;
  final double lat;
  final double lon;
  final int likeCount;
  final String? coverUrl;
  final double? distanceM;

  /// Average review rating (1-5); 0 when [ratingCount] is 0.
  final double ratingAvg;
  final int ratingCount;

  /// Works for the full spot shape and for the reduced shape embedded in feed
  /// items (no description / cover / distance).
  factory Spot.fromJson(Map<String, dynamic> j) => Spot(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    category: (j['category'] ?? 'other') as String,
    lat: _d(j['lat']),
    lon: _d(j['lon']),
    likeCount: (j['like_count'] ?? 0) as int,
    coverUrl: j['cover_url'] as String?,
    distanceM: j['distance_m'] == null ? null : _d(j['distance_m']),
    ratingAvg: j['rating_avg'] == null ? 0 : _d(j['rating_avg']),
    ratingCount: (j['rating_count'] ?? 0) as int,
  );
}

class PhotoRef {
  const PhotoRef({required this.id, required this.url, required this.thumbUrl});

  final int id;
  final String url;
  final String thumbUrl;

  factory PhotoRef.fromJson(Map<String, dynamic> j) => PhotoRef(
    id: j['id'] as int,
    url: j['url'] as String,
    thumbUrl: (j['thumb_url'] ?? j['url']) as String,
  );
}

class Author {
  const Author({required this.id, required this.displayName});

  final int id;
  final String displayName;

  factory Author.fromJson(Map<String, dynamic> j) => Author(
    id: j['id'] as int,
    displayName: (j['display_name'] ?? '') as String,
  );
}

/// Kind of an update; plain notes are the default.
enum UpdateTag {
  note('note'),
  stillGood('still_good'),
  crowded('crowded'),
  dirty('dirty'),
  closed('closed');

  const UpdateTag(this.wire);

  /// Name used by the API.
  final String wire;

  /// Unknown or absent values map to [note].
  static UpdateTag fromWire(String? w) =>
      values.firstWhere((t) => t.wire == w, orElse: () => note);
}

class FeedItem {
  const FeedItem({
    required this.id,
    required this.body,
    required this.photos,
    required this.createdAt,
    required this.author,
    required this.spot,
    this.tag = UpdateTag.note,
    this.editedAt,
  });

  final int id;
  final String body;
  final List<PhotoRef> photos;
  final DateTime createdAt;
  final Author author;
  final Spot spot;
  final UpdateTag tag;
  final DateTime? editedAt;

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
    id: j['id'] as int,
    body: (j['body'] ?? '') as String,
    photos: ((j['photos'] ?? const []) as List)
        .map((p) => PhotoRef.fromJson(p as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['created_at'] as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    spot: Spot.fromJson(j['spot'] as Map<String, dynamic>),
    tag: UpdateTag.fromWire(j['tag'] as String?),
    editedAt: j['edited_at'] == null
        ? null
        : DateTime.parse(j['edited_at'] as String),
  );
}
