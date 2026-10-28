import '../../core/models.dart';
import '../../core/paging.dart';

export '../../core/paging.dart' show CursorPage;

/// One page of an admin list.
typedef AdminPage<T> = CursorPage<T>;

/// Reporter of a report: id, name and email.
class AdminPerson {
  const AdminPerson({
    required this.id,
    required this.displayName,
    this.email = '',
  });

  final int id;
  final String displayName;
  final String email;

  factory AdminPerson.fromJson(Map<String, dynamic> j) => AdminPerson(
    id: j['id'] as int,
    displayName: (j['display_name'] ?? '') as String,
    email: (j['email'] ?? '') as String,
  );
}

/// The reported thing. When [exists] is false every other field is empty.
class AdminReportTarget {
  const AdminReportTarget({
    required this.exists,
    this.spotId,
    this.title = '',
    this.status = '',
    this.body = '',
    this.rating = 0,
    this.author,
  });

  final bool exists;
  final int? spotId;
  final String title;

  /// `active` or `hidden`.
  final String status;

  /// Update text for update reports, otherwise empty.
  final String body;

  /// Star rating (1-5) for review reports, otherwise 0.
  final int rating;
  final Author? author;

  AdminReportTarget copyWith({String? title, String? status}) =>
      AdminReportTarget(
        exists: exists,
        spotId: spotId,
        title: title ?? this.title,
        status: status ?? this.status,
        body: body,
        rating: rating,
        author: author,
      );

  factory AdminReportTarget.fromJson(Map<String, dynamic> j) =>
      AdminReportTarget(
        exists: (j['exists'] ?? false) as bool,
        spotId: j['spot_id'] as int?,
        title: (j['title'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        rating: (j['rating'] ?? 0) as int,
        author: j['author'] == null
            ? null
            : Author.fromJson(j['author'] as Map<String, dynamic>),
      );
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.createdAt,
    required this.reportCount,
    required this.reporter,
    required this.target,
  });

  final int id;

  /// `spot`, `update` or `review`.
  final String targetType;
  final int targetId;
  final String reason;
  final DateTime createdAt;
  final int reportCount;
  final AdminPerson reporter;
  final AdminReportTarget target;

  factory AdminReport.fromJson(Map<String, dynamic> j) => AdminReport(
    id: j['id'] as int,
    targetType: (j['target_type'] ?? 'spot') as String,
    targetId: j['target_id'] as int,
    reason: (j['reason'] ?? '') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    reportCount: (j['report_count'] ?? 1) as int,
    reporter: AdminPerson.fromJson(j['reporter'] as Map<String, dynamic>),
    target: AdminReportTarget.fromJson(
      (j['target'] ?? const {'exists': false}) as Map<String, dynamic>,
    ),
  );

  AdminReport copyWith({int? reportCount, AdminReportTarget? target}) =>
      AdminReport(
        id: id,
        targetType: targetType,
        targetId: targetId,
        reason: reason,
        createdAt: createdAt,
        reportCount: reportCount ?? this.reportCount,
        reporter: reporter,
        target: target ?? this.target,
      );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isAdmin,
    required this.createdAt,
    required this.spotCount,
    required this.reportsReceived,
  });

  final int id;
  final String email;
  final String displayName;
  final bool isAdmin;
  final DateTime createdAt;
  final int spotCount;
  final int reportsReceived;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    id: j['id'] as int,
    email: (j['email'] ?? '') as String,
    displayName: (j['display_name'] ?? '') as String,
    isAdmin: (j['is_admin'] ?? false) as bool,
    createdAt: DateTime.parse(j['created_at'] as String),
    spotCount: (j['spot_count'] ?? 0) as int,
    reportsReceived: (j['reports_received'] ?? 0) as int,
  );
}

class AdminSpot {
  const AdminSpot({
    required this.id,
    required this.title,
    this.description = '',
    required this.lat,
    required this.lon,
    required this.status,
    required this.likeCount,
    required this.createdAt,
    required this.author,
    required this.reportCount,
    this.tags = const [],
    this.locked = false,
  });

  final int id;
  final String title;
  final String description;
  final double lat;
  final double lon;
  final List<SpotTag> tags;

  /// Locked spots take no new updates or edits from non-admins.
  final bool locked;

  /// `active` or `hidden`.
  final String status;
  final int likeCount;
  final DateTime createdAt;
  final Author author;
  final int reportCount;

  factory AdminSpot.fromJson(Map<String, dynamic> j) => AdminSpot(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    lat: ((j['lat'] ?? 0) as num).toDouble(),
    lon: ((j['lon'] ?? 0) as num).toDouble(),
    status: (j['status'] ?? 'active') as String,
    likeCount: (j['like_count'] ?? 0) as int,
    createdAt: DateTime.parse(j['created_at'] as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    reportCount: (j['report_count'] ?? 0) as int,
    tags: SpotTag.parse(j['tags']),
    locked: (j['locked'] ?? false) as bool,
  );

  /// The editable part of a spot as the spot page has it (it is active
  /// there; date and report count are unknown and not edited).
  factory AdminSpot.fromSpot(Spot s) => AdminSpot(
    id: s.id,
    title: s.title,
    description: s.description,
    lat: s.lat,
    lon: s.lon,
    status: 'active',
    likeCount: s.likeCount,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    author: s.author ?? const Author(id: 0, displayName: ''),
    reportCount: 0,
    tags: s.tags,
    locked: s.locked,
  );

  AdminSpot copyWith({String? status, int? reportCount}) => AdminSpot(
    id: id,
    title: title,
    description: description,
    lat: lat,
    lon: lon,
    status: status ?? this.status,
    likeCount: likeCount,
    createdAt: createdAt,
    author: author,
    reportCount: reportCount ?? this.reportCount,
    tags: tags,
    locked: locked,
  );
}

/// Fields of `PATCH /admin/users/{id}`; only set fields are serialized.
class AdminUserPatch {
  const AdminUserPatch({this.displayName, this.email, this.isAdmin});

  final String? displayName;
  final String? email;
  final bool? isAdmin;

  bool get isEmpty => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
    'display_name': ?displayName,
    'email': ?email,
    'is_admin': ?isAdmin,
  };
}

/// Fields of `PATCH /admin/spots/{id}`; only set fields are serialized.
/// [lat] and [lon] are only sent together.
class AdminSpotPatch {
  const AdminSpotPatch({
    this.title,
    this.description,
    this.status,
    this.lat,
    this.lon,
    this.tags,
    this.ownerId,
    this.locked,
  });

  /// The complete new tag list (empty = remove all); null = unchanged.
  final List<SpotTag>? tags;

  /// New author of the spot.
  final int? ownerId;
  final bool? locked;
  final String? title;
  final String? description;
  final String? status;
  final double? lat;
  final double? lon;

  bool get isEmpty => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
    'title': ?title,
    'description': ?description,
    'status': ?status,
    if (lat != null && lon != null) ...{'lat': lat, 'lon': lon},
    if (tags != null) 'tags': [for (final t in SpotTag.sorted(tags!)) t.wire],
    'owner_id': ?ownerId,
    'locked': ?locked,
  };
}

/// Fields of `PATCH /admin/updates/{id}`; only set fields are serialized.
class AdminUpdatePatch {
  const AdminUpdatePatch({this.body, this.tag, this.status});

  final String? body;
  final UpdateTag? tag;

  /// `active` or `hidden`.
  final String? status;

  bool get isEmpty => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
    'body': ?body,
    'tag': ?tag?.wire,
    'status': ?status,
  };
}

/// A tag catalog entry as admins see it: the tag plus how many spots use it.
class AdminTag {
  const AdminTag(this.tag, {this.spotCount = 0});

  final SpotTag tag;
  final int spotCount;

  factory AdminTag.fromJson(Map<String, dynamic> j) =>
      AdminTag(SpotTag.fromJson(j), spotCount: (j['spot_count'] ?? 0) as int);
}

/// Fields of `POST /admin/tags` (all required) and `PATCH /admin/tags/{tag}`
/// (only set fields are sent; the key cannot change).
class AdminTagDraft {
  const AdminTagDraft({
    this.tag,
    this.nameDe,
    this.nameEn,
    this.icon,
    this.sort,
  });

  final String? tag;
  final String? nameDe;
  final String? nameEn;
  final String? icon;
  final int? sort;

  bool get isEmpty => toJson().isEmpty;

  Map<String, dynamic> toJson() => {
    'tag': ?tag,
    'name_de': ?nameDe,
    'name_en': ?nameEn,
    'icon': ?icon,
    'sort': ?sort,
  };
}
