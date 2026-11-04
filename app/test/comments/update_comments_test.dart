import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/comments/comment_button.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:app/features/comments/update_comments.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/update_tile.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'comment_helpers.dart';

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

/// The first list call fails.
class _FailingOnce extends FakeComments {
  _FailingOnce(super.pages);
  bool _failed = false;

  @override
  Future<CursorPage<Comment>> list(int updateId, {String? cursor}) {
    if (!_failed) {
      _failed = true;
      return Future.error(apiError(500, 'internal'));
    }
    return super.list(updateId, cursor: cursor);
  }
}

const me = User(id: 1, email: 'a@b.de', displayName: 'Me');
const admin = User(id: 1, email: 'a@b.de', displayName: 'Me', isAdmin: true);

/// Pumps [child] (default: the comments of [item]) on a page that can open
/// profiles, spots and the login page.
Future<void> pump(
  WidgetTester t,
  FakeComments repo, {
  User? user = me,
  FakeSpotApi? spotApi,
  FeedItem? item,
  bool expanded = false,
  Widget? child,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          body: SingleChildScrollView(
            child:
                child ??
                UpdateComments(
                  item: item ?? update(comments: 2),
                  initiallyExpanded: expanded,
                ),
          ),
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) => Text('profile ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/spot/:id',
        builder: (_, s) => Text(
          'spot ${s.pathParameters['id']} '
          'update ${s.uri.queryParameters['update']}',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(repo),
        spotApiProvider.overrideWithValue(spotApi ?? FakeSpotApi()),
        authControllerProvider.overrideWith(() => _Auth(user)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the newest two; "show all" expands the thread', (t) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(1, body: 'one'),
        comment(2, body: 'two'),
        comment(3, body: 'three'),
        comment(4, body: 'four'),
      ], null),
    });
    await pump(t, repo, item: update(comments: 4));
    expect(repo.calls, ['list:7:']);
    expect(find.text('one'), findsNothing);
    expect(find.text('two'), findsNothing);
    expect(find.text('three'), findsOneWidget);
    expect(find.text('four'), findsOneWidget);

    await t.tap(find.byKey(const Key('commentsShowAll_7')));
    await t.pumpAndSettle();
    expect(find.text('Show all 4 comments'), findsNothing);
    for (final b in ['one', 'two', 'three', 'four']) {
      expect(find.text(b), findsOneWidget);
    }
    // oldest first
    expect(
      t.getTopLeft(find.text('one')).dy,
      lessThan(t.getTopLeft(find.text('four')).dy),
    );

    await t.tap(find.byKey(const Key('commentsShowLess_7')));
    await t.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('Show all 4 comments'), findsOneWidget);
  });

  testWidgets('no comments: no request, just the composer', (t) async {
    final repo = FakeComments({});
    await pump(t, repo, item: update(comments: 0));
    expect(repo.calls, isEmpty);
    expect(find.byKey(const Key('commentInput_7')), findsOneWidget);
    expect(find.byKey(const Key('commentsShowAll_7')), findsNothing);
    expect(find.text('No comments yet. Be the first!'), findsNothing);
  });

  testWidgets('collapsed, it pages on to reach the newest', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'old')], 'c1'),
      'c1': CursorPage([comment(2, body: 'new')], null),
    });
    await pump(t, repo, item: update(comments: 2));
    expect(repo.calls, ['list:7:', 'list:7:c1']);
    expect(find.text('old'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
  });

  testWidgets('expanded, more pages load on request', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'one')], 'c1'),
      'c1': CursorPage([comment(2, body: 'two')], null),
    });
    await pump(t, repo, item: update(comments: 2), expanded: true);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsNothing);
    await t.tap(find.byKey(const Key('commentsLoadMore_7')));
    await t.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(find.byKey(const Key('commentsLoadMore_7')), findsNothing);
    expect(repo.calls, ['list:7:', 'list:7:c1']);
  });

  testWidgets('posting adds the comment and raises the count', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'first')], null),
    });
    final item = update(comments: 1);
    await pump(
      t,
      repo,
      child: Column(
        children: [
          CommentButton(item: item),
          UpdateComments(item: item),
        ],
      ),
    );

    // nothing to send yet
    final send = find.byKey(const Key('commentSend_7'));
    expect(t.widget<IconButton>(send).onPressed, isNull);
    await t.enterText(find.byKey(const Key('commentInput_7')), '  so good  ');
    await t.pump();
    await t.tap(send);
    await t.pumpAndSettle();

    expect(repo.calls, contains('create:7:so good'));
    expect(find.text('so good'), findsOneWidget);
    final input = t.widget<TextField>(find.byKey(const Key('commentInput_7')));
    expect(input.controller!.text, isEmpty);
    expect(t.widget<Text>(find.byKey(const Key('commentCount_7'))).data, '2');
  });

  testWidgets('a failed post says why and keeps the text', (t) async {
    final repo = FakeComments({null: const CursorPage([], null)})
      ..createError = apiError(429, 'quota_exceeded');
    await pump(t, repo);
    await t.enterText(find.byKey(const Key('commentInput_7')), 'again');
    await t.pump();
    await t.tap(find.byKey(const Key('commentSend_7')));
    await t.pumpAndSettle();
    expect(
      find.text(
        'You have commented a lot today. Please try again '
        'tomorrow.',
      ),
      findsOneWidget,
    );
    expect(find.text('again'), findsOneWidget);
  });

  testWidgets('a thread that cannot load offers a retry', (t) async {
    final repo = _FailingOnce({
      null: CursorPage([comment(1, body: 'back')], null),
    });
    await pump(t, repo);
    expect(find.text('Something went wrong'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsRetry_7')));
    await t.pumpAndSettle();
    expect(find.text('back'), findsOneWidget);
  });

  testWidgets('logged out: a login button instead of the composer', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1)], null),
    });
    await pump(t, repo, user: null);
    expect(find.byKey(const Key('commentInput_7')), findsNothing);
    await t.tap(find.byKey(const Key('commentsLogin_7')));
    await t.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('logged out: reporting asks for a login too', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1)], null),
    });
    await pump(t, repo, user: null);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('commentReport_1')));
    await t.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('the author\'s name and picture open their profile', (t) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(1, body: 'hey', authorId: 9, name: 'Bo'),
      ], null),
    });
    await pump(t, repo);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.byKey(const Key('authorAvatar-9')), findsOneWidget);
    await t.tap(find.byKey(const Key('authorLink-9')));
    await t.pumpAndSettle();
    expect(find.text('profile 9'), findsOneWidget);

    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('authorAvatar-9')));
    await t.pumpAndSettle();
    expect(find.text('profile 9'), findsOneWidget);
  });

  testWidgets('own comments can be deleted, by long press too', (t) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(1, body: 'mine', mine: true),
        comment(2, body: 'theirs'),
      ], null),
    });
    await pump(t, repo);
    await t.longPress(find.text('mine'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('commentReport_1')), findsNothing);
    await t.tap(find.byKey(const Key('commentDelete_1')));
    await t.pumpAndSettle();
    expect(find.text('Delete comment?'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentDeleteConfirm')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('delete:1'));
    expect(find.text('mine'), findsNothing);
    expect(find.text('theirs'), findsOneWidget);
  });

  testWidgets('someone else\'s comment can be reported, not deleted', (
    t,
  ) async {
    final repo = FakeComments({
      null: CursorPage([comment(2, body: 'theirs')], null),
    });
    final api = FakeSpotApi();
    await pump(t, repo, spotApi: api);
    await t.longPress(find.text('theirs'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('commentDelete_2')), findsNothing);
    await t.tap(find.byKey(const Key('commentReport_2')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('commentReportReason')), 'rude');
    await t.tap(find.byKey(const Key('commentReportSend')));
    await t.pumpAndSettle();
    expect(api.reports, ['comment:2:rude']);
    expect(find.text('Thanks, we will look at this comment'), findsOneWidget);
  });

  testWidgets('admins can delete any comment', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(2, body: 'theirs')], null),
    });
    await pump(t, repo, user: admin);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('commentDelete_2')), findsOneWidget);
    expect(find.byKey(const Key('commentReport_2')), findsOneWidget);
  });

  testWidgets('update tiles show their comments inline', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'under it')], null),
    });
    await pump(
      t,
      repo,
      child: UpdateTile(
        item: update(comments: 1),
        isMine: false,
        onEdit: () {},
        onDelete: () {},
        onReport: () {},
        onPhotoTap: (_) {},
      ),
    );
    expect(find.byKey(const Key('updateComments_7')), findsOneWidget);
    expect(find.text('under it'), findsOneWidget);
    expect(find.byKey(const Key('commentInput_7')), findsOneWidget);
    expect(find.byKey(const Key('commentButton_7')), findsNothing);
  });

  testWidgets('a feed card\'s comment button opens the spot at the update', (
    t,
  ) async {
    await pump(t, FakeComments({}), child: FeedCard(item: update(comments: 3)));
    expect(t.widget<Text>(find.byKey(const Key('commentCount_7'))).data, '3');
    await t.ensureVisible(find.byKey(const Key('commentButton_7')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('commentButton_7')));
    await t.pumpAndSettle();
    expect(find.text('spot 5 update 7'), findsOneWidget);
  });
}
