import 'package:flutter/foundation.dart';

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

/// A feature a spot can have. Admins manage which tags exist (`GET /tags`):
/// their names, icon and canonical order. Until that catalog is loaded the
/// seven built-in tags are used. Tags are equal when their [wire] keys are.
@immutable
class SpotTag {
  const SpotTag(
    this.wire, {
    this.nameDe = '',
    this.nameEn = '',
    this.icon = '',
    this.sort = 0,
  });

  /// Key used by the API.
  final String wire;
  final String nameDe;
  final String nameEn;

  /// Name from the app's tag icon set (see `spotTagIcon`).
  final String icon;
  final int sort;

  static const roof = SpotTag(
    'roof',
    nameDe: 'Überdacht',
    nameEn: 'Roof',
    icon: 'roof',
    sort: 10,
  );
  static const seating = SpotTag(
    'seating',
    nameDe: 'Sitzgelegenheit',
    nameEn: 'Seating',
    icon: 'seating',
    sort: 20,
  );
  static const view = SpotTag(
    'view',
    nameDe: 'Aussicht',
    nameEn: 'View',
    icon: 'view',
    sort: 30,
  );
  static const quiet = SpotTag(
    'quiet',
    nameDe: 'Ruhig',
    nameEn: 'Quiet',
    icon: 'quiet',
    sort: 40,
  );
  static const shade = SpotTag(
    'shade',
    nameDe: 'Schatten',
    nameEn: 'Shade',
    icon: 'shade',
    sort: 50,
  );
  static const water = SpotTag(
    'water',
    nameDe: 'Wasser in der Nähe',
    nameEn: 'Water nearby',
    icon: 'water',
    sort: 60,
  );
  static const lit = SpotTag(
    'lit',
    nameDe: 'Beleuchtet',
    nameEn: 'Lit',
    icon: 'lit',
    sort: 70,
  );

  /// The tags every installation starts with.
  static const builtIn = [roof, seating, view, quiet, shade, water, lit];

  static List<SpotTag> _catalog = builtIn;

  /// All tags in canonical order: the loaded catalog.
  static List<SpotTag> get values => _catalog;

  /// Replaces the catalog (after loading `GET /tags` or an admin change).
  static void setCatalog(List<SpotTag> tags) =>
      _catalog = List.unmodifiable(tags);

  /// Back to the built-in tags (tests).
  @visibleForTesting
  static void resetCatalog() => _catalog = builtIn;

  factory SpotTag.fromJson(Map<String, dynamic> j) => SpotTag(
    j['tag'] as String,
    nameDe: (j['name_de'] ?? '') as String,
    nameEn: (j['name_en'] ?? '') as String,
    icon: (j['icon'] ?? '') as String,
    sort: (j['sort'] ?? 0) as int,
  );

  /// The catalog entry for [wire], or a bare tag when it is not (yet) known.
  static SpotTag of(String wire) {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return SpotTag(wire);
  }

  /// This tag with the catalog's names and icon (the catalog may have been
  /// loaded after this tag was parsed); itself when the catalog lacks it.
  SpotTag get resolved {
    for (final t in values) {
      if (t.wire == wire) return t;
    }
    return this;
  }

  /// Display name for a language code (`de` or anything else = English);
  /// falls back to the other language, then to the key.
  String label(String languageCode) {
    final r = resolved;
    final first = languageCode == 'de' ? r.nameDe : r.nameEn;
    final second = languageCode == 'de' ? r.nameEn : r.nameDe;
    return first.isNotEmpty ? first : (second.isNotEmpty ? second : wire);
  }

  /// Null for absent values; unknown keys give a bare tag.
  static SpotTag? fromWire(String? w) => w == null || w.isEmpty ? null : of(w);

  /// Parses a JSON array of tag keys. Keys not in the catalog are kept (it may
  /// still be loading); non-strings are dropped.
  static List<SpotTag> parse(Object? json) => json is List
      ? [
          for (final e in json)
            if (e is String) ?fromWire(e),
        ]
      : const [];

  /// [tags] without duplicates, in canonical order; tags missing from the
  /// catalog come last, by key.
  static List<SpotTag> sorted(Iterable<SpotTag> tags) {
    final set = tags.toSet();
    final known = [
      for (final t in values)
        if (set.contains(t)) t,
    ];
    final rest = set.difference(known.toSet()).toList()
      ..sort((a, b) => a.wire.compareTo(b.wire));
    return [...known, ...rest];
  }

  /// Comma separated canonical list for query parameters.
  static String encode(Iterable<SpotTag> tags) =>
      sorted(tags).map((t) => t.wire).join(',');

  @override
  bool operator ==(Object other) => other is SpotTag && other.wire == wire;

  @override
  int get hashCode => wire.hashCode;

  @override
  String toString() => 'SpotTag($wire)';
}

class Spot {
  const Spot({
    required this.id,
    required this.title,
    this.description = '',
    required this.lat,
    required this.lon,
    this.likeCount = 0,
    this.coverUrl,
    this.distanceM,
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.tags = const [],
    this.author,
    this.locked = false,
  });

  final int id;
  final String title;
  final String description;
  final double lat;
  final double lon;
  final int likeCount;
  final String? coverUrl;
  final double? distanceM;

  /// Average review rating (1-5); 0 when [ratingCount] is 0.
  final double ratingAvg;
  final int ratingCount;
  final List<SpotTag> tags;

  /// Only sent by `GET /spots/{id}`.
  final Author? author;

  /// Locked spots take no new updates or edits from non-admins. Only sent by
  /// `GET /spots/{id}`.
  final bool locked;

  /// Works for the full spot shape and for the reduced shape embedded in feed
  /// items (no description / cover / distance).
  factory Spot.fromJson(Map<String, dynamic> j) => Spot(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    lat: _d(j['lat']),
    lon: _d(j['lon']),
    likeCount: (j['like_count'] ?? 0) as int,
    coverUrl: _nonEmpty(j['cover_url'] as String?),
    distanceM: j['distance_m'] == null ? null : _d(j['distance_m']),
    ratingAvg: j['rating_avg'] == null ? 0 : _d(j['rating_avg']),
    ratingCount: (j['rating_count'] ?? 0) as int,
    tags: SpotTag.parse(j['tags']),
    author: j['author'] == null
        ? null
        : Author.fromJson(j['author'] as Map<String, dynamic>),
    locked: (j['locked'] ?? false) as bool,
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
    this.updateCount = 1,
  });

  final int id;
  final String body;
  final List<PhotoRef> photos;
  final DateTime createdAt;
  final Author author;
  final Spot spot;
  final UpdateTag tag;
  final DateTime? editedAt;

  /// How many updates the spot has (the feed shows one card per spot).
  final int updateCount;

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
    updateCount: (j['update_count'] as num?)?.toInt() ?? 1,
  );
}

/// The API sends "" where there is no value; that must not look like a URL.
String? _nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v;
