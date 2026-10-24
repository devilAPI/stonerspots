import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('User.isAdmin defaults to false and parses is_admin', () {
    final a = User.fromJson({'id': 1, 'email': 'a', 'display_name': 'A'});
    expect(a.isAdmin, isFalse);
    final b = User.fromJson({
      'id': 1,
      'email': 'a',
      'display_name': 'A',
      'is_admin': true,
    });
    expect(b.isAdmin, isTrue);
    expect(a == b, isFalse);
    expect(a, User.fromJson({'id': 1, 'email': 'a', 'display_name': 'A'}));
  });

  test('AdminReport parses an existing update target', () {
    final r = AdminReport.fromJson({
      'id': 1,
      'target_type': 'update',
      'target_id': 9,
      'reason': 'spam',
      'created_at': '2026-10-01T10:00:00Z',
      'report_count': 3,
      'reporter': {'id': 2, 'display_name': 'Rita', 'email': 'r@x.de'},
      'target': {
        'exists': true,
        'spot_id': 5,
        'title': 'Bench',
        'status': 'hidden',
        'body': 'hello',
        'author': {'id': 1, 'display_name': 'Al'},
      },
    });
    expect(r.id, 1);
    expect(r.targetType, 'update');
    expect(r.reportCount, 3);
    expect(r.reporter.email, 'r@x.de');
    expect(r.createdAt.isUtc, isTrue);
    expect(r.target.exists, isTrue);
    expect(r.target.spotId, 5);
    expect(r.target.title, 'Bench');
    expect(r.target.status, 'hidden');
    expect(r.target.body, 'hello');
    expect(r.target.author?.displayName, 'Al');
  });

  test('AdminReport parses a review target with rating', () {
    Map<String, dynamic> base(Map<String, dynamic> target) => {
      'id': 1,
      'target_type': 'review',
      'target_id': 9,
      'reason': 'spam',
      'created_at': '2026-10-01T10:00:00Z',
      'report_count': 3,
      'reporter': {'id': 2, 'display_name': 'Rita', 'email': 'r@x.de'},
      'target': target,
    };
    final r = AdminReport.fromJson(
      base({
        'exists': true,
        'spot_id': 5,
        'title': 'Bench',
        'status': 'active',
        'body': 'nice',
        'rating': 4,
        'author': {'id': 1, 'display_name': 'Al'},
      }),
    );
    expect(r.targetType, 'review');
    expect(r.target.rating, 4);
    expect(r.target.body, 'nice');
    expect(r.target.copyWith(status: 'hidden').rating, 4);
    expect(
      AdminReport.fromJson(base({'exists': false, 'body': ''})).target.rating,
      0,
    );
  });

  test('AdminReport parses a missing target', () {
    final r = AdminReport.fromJson({
      'id': 1,
      'target_type': 'spot',
      'target_id': 5,
      'reason': 'x',
      'created_at': '2026-10-01T10:00:00Z',
      'report_count': 1,
      'reporter': {'id': 2, 'display_name': 'Rita', 'email': 'r@x.de'},
      'target': {'exists': false},
    });
    expect(r.target.exists, isFalse);
    expect(r.target.spotId, isNull);
    expect(r.target.title, '');
    expect(r.target.author, isNull);
  });

  test('AdminUser and AdminSpot parse', () {
    final u = AdminUser.fromJson({
      'id': 3,
      'email': 'u@x.de',
      'display_name': 'U',
      'is_admin': true,
      'created_at': '2026-01-02T00:00:00Z',
      'spot_count': 4,
      'reports_received': 2,
    });
    expect(u.isAdmin, isTrue);
    expect(u.spotCount, 4);
    expect(u.reportsReceived, 2);
    final s = AdminSpot.fromJson({
      'id': 7,
      'title': 'Lake',
      'category': 'lake',
      'lat': 48.1,
      'lon': 11.5,
      'status': 'active',
      'like_count': 5,
      'created_at': '2026-01-02T00:00:00Z',
      'author': {'id': 1, 'display_name': 'Al'},
      'report_count': 0,
    });
    expect(s.title, 'Lake');
    expect(s.likeCount, 5);
    expect(s.author.displayName, 'Al');
    expect(s.status, 'active');
  });

  test('AdminPage.fromJson reads items and next_cursor', () {
    final p = AdminPage.fromJson({
      'items': [
        {'id': 1},
      ],
      'next_cursor': 'abc',
    }, (j) => j['id'] as int);
    expect(p.items, [1]);
    expect(p.nextCursor, 'abc');
    final last = AdminPage.fromJson({
      'items': <dynamic>[],
      'next_cursor': null,
    }, (j) => j['id'] as int);
    expect(last.nextCursor, isNull);
  });

  test('patches serialize only set fields', () {
    expect(const AdminUserPatch().toJson(), isEmpty);
    expect(const AdminUserPatch(isAdmin: false).toJson(), {'is_admin': false});
    expect(const AdminSpotPatch(title: 'x', lat: 1).toJson(), {'title': 'x'});
    expect(const AdminSpotPatch(lat: 1, lon: 2).toJson(), {'lat': 1, 'lon': 2});
  });
}
