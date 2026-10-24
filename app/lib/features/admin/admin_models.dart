import '../../core/models.dart';

/// One page of an admin list plus the cursor for the next one (null = end).
class AdminPage<T> {
  const AdminPage(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;

  factory AdminPage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) => AdminPage(
    ((json['items'] ?? const []) as List)
        .map((e) => parse(e as Map<String, dynamic>))
        .toList(),
    json['next_cursor'] as String?,
  );
}

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
    this.author,
  });

  final bool exists;
  final int? spotId;
  final String title;

  /// `active` or `hidden`.
  final String status;

  /// Update text for update reports, otherwise empty.
  final String body;
  final Author? author;

  factory AdminReportTarget.fromJson(Map<String, dynamic> j) =>
      AdminReportTarget(
        exists: (j['exists'] ?? false) as bool,
        spotId: j['spot_id'] as int?,
        title: (j['title'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        body: (j['body'] ?? '') as String,
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

  /// `spot` or `update`.
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
    required this.category,
    required this.lat,
    required this.lon,
    required this.status,
    required this.likeCount,
    required this.createdAt,
    required this.author,
    required this.reportCount,
  });

  final int id;
  final String title;
  final String category;
  final double lat;
  final double lon;

  /// `active` or `hidden`.
  final String status;
  final int likeCount;
  final DateTime createdAt;
  final Author author;
  final int reportCount;

  factory AdminSpot.fromJson(Map<String, dynamic> j) => AdminSpot(
    id: j['id'] as int,
    title: (j['title'] ?? '') as String,
    category: (j['category'] ?? 'other') as String,
    lat: ((j['lat'] ?? 0) as num).toDouble(),
    lon: ((j['lon'] ?? 0) as num).toDouble(),
    status: (j['status'] ?? 'active') as String,
    likeCount: (j['like_count'] ?? 0) as int,
    createdAt: DateTime.parse(j['created_at'] as String),
    author: Author.fromJson(j['author'] as Map<String, dynamic>),
    reportCount: (j['report_count'] ?? 0) as int,
  );
}
