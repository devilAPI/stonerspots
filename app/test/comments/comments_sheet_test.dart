import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/comments/comment_button.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:app/features/comments/comments_sheet.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/update_tile.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Pumps [child] (default: a comment button for [item]) and returns what
/// the sheet asked for.
Future<List<String>> pump(
  WidgetTester t,
  FakeComments repo, {
  User? user = me,
  FakeSpotApi? spotApi,
  FeedItem? item,
  Widget? child,
}) async {
  final events = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        commentsRepositoryProvider.overrideWithValue(repo),
        spotApiProvider.overrideWithValue(spotApi ?? FakeSpotApi()),
        authControllerProvider.overrideWith(() => _Auth(user)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body:
              child ??
              Column(
                children: [
                  CommentButton(item: item ?? update(comments: 2)),
                  Expanded(
                    child: CommentsSheet(
                      key: const Key('inlineSheet'),
                      updateId: 70,
                      baseCount: 0,
                      onLogin: () => events.add('login'),
                    ),
                  ),
                ],
              ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return events;
}

Finder inSheet(Finder f) =>
    find.descendant(of: find.byKey(const Key('inlineSheet')), matching: f);

void main() {
  testWidgets('the button shows the count and opens the thread', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'first'), comment(2)], null),
    });
    await pump(t, repo, child: CommentButton(item: update(comments: 2)));
    expect(find.text('2'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentButton_7')));
    await t.pumpAndSettle();
    expect(find.byType(CommentsSheet), findsOneWidget);
    expect(find.text('Comments'), findsWidgets);
    expect(find.text('first'), findsOneWidget);
    expect(repo.calls, ['list:7:']);
  });

  testWidgets('posting adds the comment and raises the count', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'first')], null),
    });
    await pump(t, repo, child: CommentButton(item: update(comments: 1)));
    await t.tap(find.byKey(const Key('commentButton_7')));
    await t.pumpAndSettle();

    // nothing to send yet
    final send = find.byKey(const Key('commentSend'));
    expect(t.widget<IconButton>(send).onPressed, isNull);
    await t.enterText(find.byKey(const Key('commentInput')), '  so good  ');
    await t.pump();
    await t.tap(send);
    await t.pumpAndSettle();

    expect(repo.calls, contains('create:7:so good'));
    expect(find.text('so good'), findsOneWidget);
    final input = t.widget<TextField>(find.byKey(const Key('commentInput')));
    expect(input.controller!.text, isEmpty);
    // the button behind the sheet counts it
    expect(t.widget<Text>(find.byKey(const Key('commentCount_7'))).data, '2');
  });

  testWidgets('a failed post says why and keeps the text', (t) async {
    final repo = FakeComments({null: const CursorPage([], null)})
      ..createError = apiError(429, 'quota_exceeded');
    await pump(t, repo);
    await t.enterText(inSheet(find.byKey(const Key('commentInput'))), 'again');
    await t.pump();
    await t.tap(inSheet(find.byKey(const Key('commentSend'))));
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

  testWidgets('paging', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1, body: 'one')], 'c1'),
      'c1': CursorPage([comment(2, body: 'two')], null),
    });
    await pump(t, repo);
    expect(find.text('one'), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsLoadMore')));
    await t.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(find.byKey(const Key('commentsLoadMore')), findsNothing);
    expect(repo.calls, ['list:70:', 'list:70:c1']);
  });

  testWidgets('empty thread', (t) async {
    await pump(t, FakeComments({}));
    expect(
      inSheet(find.text('No comments yet. Be the first!')),
      findsOneWidget,
    );
  });

  testWidgets('a thread that cannot load offers a retry', (t) async {
    final repo = _FailingOnce({
      null: CursorPage([comment(1, body: 'back')], null),
    });
    await pump(t, repo);
    expect(inSheet(find.text('Something went wrong')), findsOneWidget);
    await t.tap(find.byKey(const Key('commentsRetry')));
    await t.pumpAndSettle();
    expect(find.text('back'), findsOneWidget);
  });

  testWidgets('logged out: no composer, a login button instead', (t) async {
    final repo = FakeComments({
      null: CursorPage([comment(1)], null),
    });
    final events = await pump(t, repo, user: null);
    expect(find.byKey(const Key('commentInput')), findsNothing);
    await t.tap(find.byKey(const Key('commentsLogin')));
    expect(events, ['login']);

    // reporting needs a login too
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('commentReport_1')));
    await t.pumpAndSettle();
    expect(events, ['login', 'login']);
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

  testWidgets('feed cards and update tiles have the comment button', (t) async {
    final item = update(comments: 3);
    await pump(
      t,
      FakeComments({}),
      child: SingleChildScrollView(
        child: Column(
          children: [
            FeedCard(item: item),
            UpdateTile(
              item: update(id: 8, comments: 1),
              isMine: false,
              onEdit: () {},
              onDelete: () {},
              onReport: () {},
              onPhotoTap: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(t.widget<Text>(find.byKey(const Key('commentCount_7'))).data, '3');
    expect(t.widget<Text>(find.byKey(const Key('commentCount_8'))).data, '1');
    // the tile's button opens the tile's thread
    await t.ensureVisible(find.byKey(const Key('commentButton_8')));
    await t.tap(find.byKey(const Key('commentButton_8')));
    await t.pumpAndSettle();
    expect(find.byType(CommentsSheet), findsOneWidget);
  });
}
