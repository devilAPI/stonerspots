double _d(Object? v) => (v as num).toDouble();

class User {
  const User({
    required this.id,
    required this.email,
    required this.displayName,
  });

  final int id;
  final String email;
  final String displayName;

  factory User.fromJson(Map<String, dynamic> j) => User(
    id: j['id'] as int,
    email: (j['email'] ?? '') as String,
    displayName: (j['display_name'] ?? '') as String,
  );

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, email, displayName);
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

class FeedItem {
  const FeedItem({
    required this.id,
    required this.body,
    required this.photos,
    required this.createdAt,
    required this.author,
    required this.spot,
  });

  final int id;
  final String body;
  final List<PhotoRef> photos;
  final DateTime createdAt;
  final Author author;
  final Spot spot;

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
    id: j['id'] as int,
    body: (j['body'] ?? '') as String,
    photos: ((j['photos'] ?? const []) as List)
        .map((p) => PhotoRef.fromJson(p as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['created_at'] as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    spot: Spot.fromJson(j['spot'] as Map<String, dynamic>),
  );
}
