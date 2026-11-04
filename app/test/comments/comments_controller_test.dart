import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_controller.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comment_helpers.dart';

void main() {
  test('Comment and Spot parse the API shapes', () {
    final c = Comment.fromJson({
      'id': 3,
      'spot_id': 5,
      'body': 'nice',
      'created_at': '2026-11-04T10:00:00Z',
      'author': {'id': 2, 'display_name': 'Ann'},
      'mine': true,
    });
    expect(c.id, 3);
    expect(c.spotId, 5);
    expect(c.body, 'nice');
    expect(c.author.displayName, 'Ann');
    expect(c.mine, isTrue);
    expect(c.createdAt, DateTime.utc(2026, 11, 4, 10));

    final json = {'id': 5, 'title': 'S', 'lat': 1, 'lon': 2};
    expect(Spot.fromJson(json).commentCount, 0);
    expect(Spot.fromJson({...json, 'comment_count': 4}).commentCount, 4);
  });

  group('spot comments', () {
    late FakeComments repo;
    late ProviderContainer c;
    late ProviderSubscription<Paged<Comment>> sub;

    setUp(() {
      // newest first, like the API
      repo = FakeComments({
        null: CursorPage([comment(3), comment(2)], 'c2'),
        'c2': CursorPage([comment(1)], null),
      });
      c = ProviderContainer(
        overrides: [commentsRepositoryProvider.overrideWithValue(repo)],
      );
      // keep the auto-dispose list alive
      sub = c.listen(spotCommentsProvider(5), (_, _) {});
    });

    tearDown(() {
      sub.close();
      c.dispose();
    });

    SpotCommentsController ctrl() => c.read(spotCommentsProvider(5).notifier);
    List<int> ids() => [for (final x in sub.read().items) x.id];

    test('pages newest first', () async {
      await ctrl().load();
      expect(ids(), [3, 2]);
      expect(sub.read().hasMore, isTrue);
      await ctrl().loadMore();
      expect(ids(), [3, 2, 1]);
      expect(sub.read().hasMore, isFalse);
      expect(repo.calls, ['list:5:', 'list:5:c2']);
    });

    test('a posted comment shows on top; older pages still follow', () async {
      await ctrl().load();
      final posted = await ctrl().post('mine');
      expect(posted.id, 100);
      expect(ids(), [100, 3, 2]);
      await ctrl().loadMore();
      expect(ids(), [100, 3, 2, 1]);
      expect(repo.calls, contains('create:5:mine'));
    });

    test('delete removes the comment; 404 counts as deleted', () async {
      await ctrl().load();
      await ctrl().delete(comment(3));
      expect(ids(), [2]);
      repo.deleteError = apiError(404, 'not_found');
      await ctrl().delete(comment(2));
      expect(ids(), isEmpty);
    });

    test('other delete errors keep the comment', () async {
      await ctrl().load();
      repo.deleteError = apiError(500, 'internal');
      await expectLater(ctrl().delete(comment(3)), throwsA(anything));
      expect(ids(), [3, 2]);
    });
  });
}
