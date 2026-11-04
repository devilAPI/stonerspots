import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/admin/admin_screen.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../comments/comment_helpers.dart';

AdminReport _r(int id, int commentId) => AdminReport(
  id: id,
  targetType: 'comment',
  targetId: commentId,
  reason: 'reason-$id',
  createdAt: DateTime.utc(2026, 10, 1, 10),
  reportCount: 3,
  reporter: AdminPerson(id: 2, displayName: 'Rita$id', email: 'r$id@x.de'),
  target: const AdminReportTarget(
    exists: true,
    spotId: 100,
    title: 'Spot100',
    status: 'hidden',
    body: 'rude words',
    author: Author(id: 7, displayName: 'Authy'),
  ),
);

class _Fake implements AdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  List<AdminReport> items = [];
  final dismissCalls = <(String, int, bool)>[];

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async => AdminPage(items, null);

  @override
  Future<int> dismissReports({
    required String targetType,
    required int targetId,
    required bool restore,
  }) async {
    dismissCalls.add((targetType, targetId, restore));
    return 1;
  }
}

Future<void> _pump(WidgetTester t, _Fake repo, FakeComments comments) async {
  t.view.physicalSize = const Size(1100, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        commentsRepositoryProvider.overrideWithValue(comments),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const AdminScreen()),
            GoRoute(
              path: '/spot/:id',
              builder: (_, s) => Text('SPOT ${s.pathParameters['id']}'),
            ),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  test('the report target of a comment names its spot', () {
    final t = AdminReportTarget.fromJson({
      'exists': true,
      'spot_id': 1,
      'title': 'Bench',
      'body': 'x',
    });
    expect(t.spotId, 1);
    expect(t.title, 'Bench');
    expect(AdminReportTarget.fromJson({'exists': false}).spotId, isNull);
  });

  testWidgets('a comment report shows the comment and its author', (t) async {
    await _pump(t, _Fake()..items = [_r(1, 30)], FakeComments({}));
    expect(find.text('Comment'), findsOneWidget);
    expect(find.text('rude words'), findsOneWidget);
    expect(find.text('Comment on Spot100'), findsOneWidget);
    expect(find.text('Authy'), findsOneWidget);
    expect(find.text('Remove comment'), findsOneWidget);
    expect(find.byKey(const Key('report-open-1')), findsOneWidget);
    // the spot is not what was reported
    expect(find.byKey(const Key('report-remove-1')), findsNothing);
    expect(find.byKey(const Key('report-edit-spot-1')), findsNothing);
  });

  testWidgets('remove comment: confirm, delete, drop its reports', (t) async {
    final comments = FakeComments({});
    await _pump(
      t,
      _Fake()..items = [_r(1, 30), _r(2, 30), _r(3, 31)],
      comments,
    );
    await _tap(t, 'report-remove-target-1');
    expect(
      find.textContaining('deletes this comment permanently'),
      findsOneWidget,
    );
    await _tap(t, 'confirm-remove-target');
    expect(comments.calls, ['delete:30']);
    expect(find.byKey(const Key('report-1')), findsNothing);
    expect(find.byKey(const Key('report-2')), findsNothing);
    expect(find.byKey(const Key('report-3')), findsOneWidget);
    expect(find.text('Comment removed'), findsOneWidget);
  });

  testWidgets('a comment that is gone already counts as removed', (t) async {
    final comments = FakeComments({})..deleteError = apiError(404, 'not_found');
    await _pump(t, _Fake()..items = [_r(1, 30)], comments);
    await _tap(t, 'report-remove-target-1');
    await _tap(t, 'confirm-remove-target');
    expect(find.byKey(const Key('report-1')), findsNothing);
    expect(find.text('Comment removed'), findsOneWidget);
  });

  testWidgets('dismiss all and restore sends target_type comment', (t) async {
    final repo = _Fake()..items = [_r(1, 30)];
    await _pump(t, repo, FakeComments({}));
    await _tap(t, 'report-more-1');
    await _tap(t, 'report-dismiss-all-restore-1');
    await _tap(t, 'confirm-dismiss-all');
    expect(repo.dismissCalls, [('comment', 30, true)]);
  });
}
