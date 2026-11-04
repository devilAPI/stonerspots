import 'package:app/core/models.dart';
import 'package:app/features/activity/activity_models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = 'https://x.test/api/v1/media/avatars/7.jpg';

Map<String, dynamic> _author([Object? avatar = _url]) => {
  'id': 7,
  'display_name': 'Alice',
  'avatar_url': ?avatar,
};

void main() {
  group('avatar_url', () {
    test('authors: with, without, null, empty and not a string', () {
      expect(Author.fromJson(_author()).avatarUrl, _url);
      expect(Author.fromJson(_author(null)).avatarUrl, isNull);
      expect(
        Author.fromJson({'id': 7, 'display_name': 'A', 'avatar_url': null})
            .avatarUrl,
        isNull,
      );
      expect(Author.fromJson(_author('')).avatarUrl, isNull);
      expect(Author.fromJson(_author(42)).avatarUrl, isNull);
    });

    test('the logged-in user, and its equality', () {
      final j = {
        'id': 1,
        'email': 'a@b.de',
        'display_name': 'Me',
        'avatar_url': _url,
      };
      final u = User.fromJson(j);
      expect(u.avatarUrl, _url);
      expect(User.fromJson({...j}..remove('avatar_url')).avatarUrl, isNull);
      expect(u, User.fromJson(j));
      expect(u.hashCode, User.fromJson(j).hashCode);
      final without = u.withAvatarUrl(null);
      expect(without.avatarUrl, isNull);
      expect(without, isNot(u));
      expect(without.withAvatarUrl(_url), u);
    });

    test('public profiles keep it when followed', () {
      final p = UserProfile.fromJson({
        'id': 7,
        'display_name': 'Alice',
        'created_at': '2025-01-01T00:00:00Z',
        'avatar_url': _url,
      });
      expect(p.avatarUrl, _url);
      expect(p.withFollowing(true).avatarUrl, _url);
      expect(
        UserProfile.fromJson({
          'id': 7,
          'display_name': 'Alice',
          'created_at': '2025-01-01T00:00:00Z',
        }).avatarUrl,
        isNull,
      );
    });

    test('spot list items carry their owner, or none', () {
      final base = {'id': 1, 'title': 'Bench', 'lat': 1.0, 'lon': 2.0};
      final owned = Spot.fromJson({...base, 'author': _author()});
      expect(owned.author?.id, 7);
      expect(owned.author?.avatarUrl, _url);
      expect(Spot.fromJson({...base, 'author': null}).author, isNull);
      expect(Spot.fromJson(base).author, isNull);
    });

    test('updates, reviews, comments and activity', () {
      final item = FeedItem.fromJson({
        'id': 3,
        'body': '',
        'created_at': '2026-01-01T00:00:00Z',
        'author': _author(),
        'spot': {'id': 1, 'title': 'B', 'lat': 1, 'lon': 2},
      });
      expect(item.author.avatarUrl, _url);

      final review = Review.fromJson({
        'id': 1,
        'rating': 4,
        'created_at': '2026-01-01T00:00:00Z',
        'author': _author(null),
      });
      expect(review.author.avatarUrl, isNull);

      final comment = Comment.fromJson({
        'id': 1,
        'body': 'hi',
        'created_at': '2026-01-01T00:00:00Z',
        'author': _author(),
      });
      expect(comment.author.avatarUrl, _url);

      final activity = ActivityItem.fromJson({
        'id': 1,
        'kind': 'follow',
        'created_at': '2026-01-01T00:00:00Z',
        'actor': _author(),
      });
      expect(activity!.actor.avatarUrl, _url);
    });

    test('admin user rows', () {
      final j = {
        'id': 7,
        'email': 'a@b.de',
        'display_name': 'Alice',
        'created_at': '2025-01-01T00:00:00Z',
        'avatar_url': _url,
      };
      final u = AdminUser.fromJson(j);
      expect(u.avatarUrl, _url);
      expect(u.withoutAvatar().avatarUrl, isNull);
      expect(u.withoutAvatar().displayName, 'Alice');
      expect(
        AdminUser.fromJson({...j}..remove('avatar_url')).avatarUrl,
        isNull,
      );
    });
  });
}
