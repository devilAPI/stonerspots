import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:app/features/comments/spot_comments.dart';
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
  Future<CursorPage<Comment>> list(int spotId, {String? cursor}) {
    if (!_failed) {
      _failed = true;
      return Future.error(apiError(500, 'internal'));
    }
    return super.list(spotId, cursor: cursor);
  }
}

const me = User(id: 1, email: 'a@b.de', displayName: 'Me');
const admin = User(id: 1, email: 'a@b.de', displayName: 'Me', isAdmin: true);

FeedItem update({int id = 7}) => FeedItem(
  id: id,
  body: 'hello',
  photos: const [],
  createdAt: DateTime(2026, 10, 1),
  author: const Author(id: 2, displayName: 'Ann'),
  spot: const Spot(id: 5, title: 'Lake bench', lat: 1, lon: 2),
);

/// Pumps [child] (default: the comments section of spot 5 with [count]
/// comments) on a page that can open profiles and the login page.
Future<void> pump(
  WidgetTester t,
  FakeComments repo, {
  User? user = me,
  FakeSpotApi? spotApi,
  int count = 2,
  bool canWrite = true,
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
                SpotComments(spotId: 5, count: count, canWrite: canWrite),
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
        builder: (_, s) => Text('spot ${s.pathParameters['id']}'),
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
  testWidgets('a section with a heading; the composer comes first', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'one')], null),
    });
    await pump(t, repo, count: 1);
    expect(find.text('Comments'), findsOneWidget);
    final heading = t.widget<Text>(find.byKey(const Key('commentsHeading')));
    final theme = Theme.of(t.element(find.byKey(const Key('commentsHeading'))));
    expect(heading.style, theme.textTheme.titleLarge);
    expect(
      t.getTopLeft(find.byKey(const Key('commentInput'))).dy,
      lessThan(t.getTopLeft(find.text('one')).dy),
    );
  });

  testWidgets('shows the newest three; "show all" expands the section', (
    t,
  ) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(4, body: 'four'),
        comment(3, body: 'three'),
        comment(2, body: 'two'),
        comment(1, body: 'one'),
      ], null),
    });
    await pump(t, repo, count: 4);
    expect(repo.calls, ['list:5:']);
    expect(find.text('four'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('one'), findsNothing);
    // newest first
    expect(
      t.getTopLeft(find.text('four')).dy,
      lessThan(t.getTopLeft(find.text('two')).dy),
    );

    await t.tap(find.byKey(const Key('commentsShowAll')));
    await t.pumpAndSettle();
    expect(find.text('Show all 4 comments'), findsNothing);
    for (final b in ['one', 'two', 'three', 'four']) {
      expect(find.text(b), findsOneWidget);
    }

    await t.tap(find.byKey(const Key('commentsShowLess')));
    await t.pumpAndSettle();
    expect(find.text('one'), findsNothing);
    expect(find.text('Show all 4 comments'), findsOneWidget);
  });

  testWidgets('no comments: no request, the composer and a hint', (t) async {
    final repo = FakeComments({});
    await pump(t, repo, count: 0);
    expect(repo.calls, isEmpty);
    expect(find.byKey(const Key('commentInput')), findsOneWidget);
    expect(find.byKey(const Key('commentsShowAll')), findsNothing);
    expect(find.text('No comments yet. Be the first!'), findsOneWidget);
  });

  testWidgets('expanded, older pages load on request', (t) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(5, body: 'e'),
        comment(4, body: 'd'),
        comment(3, body: 'c'),
        comment(2, body: 'b'),
      ], 'c2'),
      'c2': CursorPage([comment(1, body: 'a')], null),
    });
    await pump(t, repo, count: 5);
    expect(find.text('Show all 5 comments'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsShowAll')));
    await t.pumpAndSettle();
    expect(find.text('b'), findsOneWidget);
    expect(find.text('a'), findsNothing);
    await t.tap(find.byKey(const Key('commentsLoadMore')));
    await t.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.byKey(const Key('commentsLoadMore')), findsNothing);
    expect(repo.calls, ['list:5:', 'list:5:c2']);
  });

  testWidgets('posting puts the comment on top and raises the count', (
    t,
  ) async {
    final repo = FakeComments({
      null: CursorPage([
        comment(3, body: 'c'),
        comment(2, body: 'b'),
        comment(1, body: 'a'),
      ], null),
    });
    await pump(t, repo, count: 3);
    expect(find.byKey(const Key('commentsShowAll')), findsNothing);

    // nothing to send yet
    final send = find.byKey(const Key('commentSend'));
    expect(t.widget<IconButton>(send).onPressed, isNull);
    await t.enterText(find.byKey(const Key('commentInput')), '  so good  ');
    await t.pump();
    await t.tap(send);
    await t.pumpAndSettle();

    expect(repo.calls, contains('create:5:so good'));
    expect(find.text('so good'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('so good')).dy,
      lessThan(t.getTopLeft(find.text('c')).dy),
    );
    final input = t.widget<TextField>(find.byKey(const Key('commentInput')));
    expect(input.controller!.text, isEmpty);
    // four now: the oldest folds away behind "show all"
    expect(find.text('a'), findsNothing);
    expect(find.text('Show all 4 comments'), findsOneWidget);
  });

  testWidgets('a failed post says why and keeps the text', (t) async {
    final repo = FakeComments({null: const CursorPage([], null)})
      ..createError = apiError(429, 'quota_exceeded');
    await pump(t, repo);
    await t.enterText(find.byKey(const Key('commentInput')), 'again');
    await t.pump();
    await t.tap(find.byKey(const Key('commentSend')));
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

  testWidgets('a section that cannot load offers a retry', (t) async {
    final repo = _FailingOnce({
      null: CursorPage([comment(1, body: 'back')], null),
    });
    await pump(t, repo);
    expect(find.text('Something went wrong'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsRetry')));
    await t.pumpAndSettle();
    expect(find.text('back'), findsOneWidget);
  });

  testWidgets('logged out: a login button instead of the composer', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1)], null),
    });
    await pump(t, repo, user: null);
    expect(find.byKey(const Key('commentInput')), findsNothing);
    expect(find.text('Log in to comment'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsLogin')));
    await t.pumpAndSettle();
    expect(find.text('LOGIN'), findsOneWidget);
  });

  testWidgets('locked spot: no composer, comments still show', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'from before')], null),
    });
    await pump(t, repo, canWrite: false, count: 1);
    expect(find.byKey(const Key('commentInput')), findsNothing);
    expect(find.byKey(const Key('commentsLocked')), findsOneWidget);
    expect(find.text('from before'), findsOneWidget);
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
        comment(2, body: 'theirs'),
        comment(1, body: 'mine', mine: true),
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

  testWidgets('update tiles have no comments of their own', (t) async {
    final repo = FakeComments({});
    await pump(
      t,
      repo,
      child: UpdateTile(
        item: update(),
        isMine: false,
        onEdit: () {},
        onDelete: () {},
        onReport: () {},
        onPhotoTap: (_) {},
      ),
    );
    expect(find.text('hello'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
    expect(repo.calls, isEmpty);
  });

  testWidgets('feed cards have no comment button', (t) async {
    await pump(t, FakeComments({}), child: FeedCard(item: update()));
    expect(find.text('hello'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);
  });
}
