import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_controller.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'comment_helpers.dart';

void main() {
  test('Comment and FeedItem parse the API shapes', () {
    final c = Comment.fromJson({
      'id': 3,
      'update_id': 7,
      'body': 'nice',
      'created_at': '2026-11-04T10:00:00Z',
      'author': {'id': 2, 'display_name': 'Ann'},
      'mine': true,
    });
    expect(c.id, 3);
    expect(c.updateId, 7);
    expect(c.body, 'nice');
    expect(c.author.displayName, 'Ann');
    expect(c.mine, isTrue);
    expect(c.createdAt, DateTime.utc(2026, 11, 4, 10));

    final json = {
      'id': 7,
      'body': '',
      'created_at': '2026-11-04T10:00:00Z',
      'author': {'id': 2, 'display_name': 'Ann'},
      'spot': {'id': 5, 'title': 'S', 'lat': 1, 'lon': 2},
    };
    expect(FeedItem.fromJson(json).commentCount, 0);
    expect(FeedItem.fromJson({...json, 'comment_count': 4}).commentCount, 4);
  });

  group('thread', () {
    late FakeComments repo;
    late ProviderContainer c;
    late ProviderSubscription<Paged<Comment>> sub;

    setUp(() {
      repo = FakeComments({
        null: CursorPage([comment(1), comment(2)], 'c2'),
        'c2': CursorPage([comment(3)], null),
      });
      c = ProviderContainer(
        overrides: [commentsRepositoryProvider.overrideWithValue(repo)],
      );
      // keep the auto-dispose thread alive
      sub = c.listen(commentThreadProvider(7), (_, _) {});
    });

    tearDown(() {
      sub.close();
      c.dispose();
    });

    CommentThreadController ctrl() => c.read(commentThreadProvider(7).notifier);
    List<int> ids() => [for (final x in sub.read().items) x.id];

    test('pages oldest first', () async {
      await ctrl().load();
      expect(ids(), [1, 2]);
      expect(sub.read().hasMore, isTrue);
      await ctrl().loadMore();
      expect(ids(), [1, 2, 3]);
      expect(sub.read().hasMore, isFalse);
      expect(repo.calls, ['list:7:', 'list:7:c2']);
    });

    test('a posted comment shows at the end and stays in order when '
        'newer pages come in', () async {
      await ctrl().load();
      final posted = await ctrl().post('mine');
      expect(posted.id, 100);
      expect(ids(), [1, 2, 100]);
      await ctrl().loadMore();
      expect(ids(), [1, 2, 3, 100]);
      expect(repo.calls, contains('create:7:mine'));
    });

    test('delete removes the comment; 404 counts as deleted', () async {
      await ctrl().load();
      await ctrl().delete(comment(1));
      expect(ids(), [2]);
      repo.deleteError = apiError(404, 'not_found');
      await ctrl().delete(comment(2));
      expect(ids(), isEmpty);
    });

    test('other delete errors keep the comment', () async {
      await ctrl().load();
      repo.deleteError = apiError(500, 'internal');
      await expectLater(ctrl().delete(comment(1)), throwsA(anything));
      expect(ids(), [1, 2]);
    });
  });

  group('counts', () {
    test('adjustments apply to the count the update came with', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final counts = c.read(commentCountsProvider.notifier);
      final item = update(comments: 2);
      expect(CommentCounts.of(c.read(commentCountsProvider), item), 2);
      counts.adjust(7, 2, 1);
      counts.adjust(7, 2, 1);
      expect(CommentCounts.of(c.read(commentCountsProvider), item), 4);
      counts.adjust(7, 2, -1);
      expect(CommentCounts.of(c.read(commentCountsProvider), item), 3);
      // a reload with a newer server count wins
      expect(
        CommentCounts.of(c.read(commentCountsProvider), update(comments: 5)),
        5,
      );
      // never below zero
      counts.adjust(8, 0, -1);
      expect(CommentCounts.of(c.read(commentCountsProvider), update(id: 8)), 0);
    });
  });
}
