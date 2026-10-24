import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/admin/admin_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AdminReport _r(
  int id,
  String type,
  int targetId, {
  String body = '',
  int rating = 0,
}) => AdminReport(
  id: id,
  targetType: type,
  targetId: targetId,
  reason: 'reason-$id',
  createdAt: DateTime.utc(2026, 10, 1, 10),
  reportCount: 3,
  reporter: AdminPerson(id: 2, displayName: 'Rita$id', email: 'r$id@x.de'),
  target: AdminReportTarget(
    exists: true,
    spotId: 100,
    title: 'Spot100',
    status: 'hidden',
    body: body,
    rating: rating,
    author: Author(id: 7, displayName: 'Authy'),
  ),
);

class _Fake implements AdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  List<AdminReport> items = [];
  final deletedReviews = <int>[];
  final deletedUpdates = <int>[];
  final dismissCalls = <(String, int, bool)>[];
  ApiException? error;

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async => AdminPage(items, null);

  @override
  Future<void> deleteReview(int id) async {
    if (error != null) throw error!;
    deletedReviews.add(id);
  }

  @override
  Future<void> deleteUpdate(int id) async {
    if (error != null) throw error!;
    deletedUpdates.add(id);
  }

  @override
  Future<int> dismissReports({
    required String targetType,
    required int targetId,
    required bool restore,
  }) async {
    dismissCalls.add((targetType, targetId, restore));
    return 2;
  }
}

Future<void> _pump(WidgetTester tester, _Fake repo, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
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
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

const _sizes = {
  'phone': Size(400, 800),
  'landscape': Size(844, 390),
  'wide': Size(1100, 700),
};

void main() {
  for (final e in _sizes.entries) {
    group('review/update moderation ${e.key}', () {
      testWidgets('review tile shows details', (tester) async {
        final repo = _Fake()
          ..items = [_r(1, 'review', 9, body: 'Great!', rating: 4)];
        await _pump(tester, repo, e.value);
        expect(find.text('Review'), findsOneWidget);
        expect(find.text('Great!'), findsOneWidget);
        expect(find.textContaining('Spot100'), findsWidgets);
        expect(find.textContaining('Authy'), findsOneWidget);
        expect(find.text('Hidden'), findsOneWidget);
        expect(find.text('3 reports'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNWidgets(4));
        expect(find.byIcon(Icons.star_border), findsNWidgets(1));
        expect(find.byKey(const Key('report-remove-target-1')), findsOneWidget);
        expect(find.text('Remove review'), findsOneWidget);
        expect(find.byKey(const Key('report-open-1')), findsOneWidget);
        expect(find.byKey(const Key('report-remove-1')), findsNothing);
      });

      testWidgets('empty review text is hidden', (tester) async {
        final repo = _Fake()..items = [_r(1, 'review', 9, rating: 5)];
        await _pump(tester, repo, e.value);
        expect(find.text('Review'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNWidgets(5));
      });

      testWidgets('update tile shows label, text and remove action', (
        tester,
      ) async {
        final repo = _Fake()..items = [_r(2, 'update', 8, body: 'upd-text')];
        await _pump(tester, repo, e.value);
        expect(find.text('Update'), findsOneWidget);
        expect(find.text('upd-text'), findsOneWidget);
        expect(find.text('Remove update'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
      });

      testWidgets('remove review: confirm, delete, drop all its reports', (
        tester,
      ) async {
        final repo = _Fake()
          ..items = [
            _r(1, 'review', 9, body: 'a', rating: 3),
            _r(2, 'review', 9, body: 'a', rating: 3),
            _r(3, 'review', 10, body: 'b', rating: 2),
            _r(4, 'update', 9, body: 'u'),
          ];
        await _pump(tester, repo, e.value);
        await _tap(tester, 'report-remove-target-1');
        expect(
          find.textContaining('deletes this review permanently'),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.deletedReviews, isEmpty);
        await _tap(tester, 'report-remove-target-1');
        await _tap(tester, 'confirm-remove-target');
        expect(repo.deletedReviews, [9]);
        expect(find.byKey(const Key('report-1')), findsNothing);
        expect(find.byKey(const Key('report-2')), findsNothing);
        expect(find.byKey(const Key('report-3')), findsOneWidget);
        expect(find.byKey(const Key('report-4')), findsOneWidget);
        expect(find.text('Review removed'), findsOneWidget);
      });

      testWidgets('remove update calls deleteUpdate', (tester) async {
        final repo = _Fake()
          ..items = [
            _r(1, 'update', 8, body: 'u'),
            _r(2, 'update', 8, body: 'u'),
          ];
        await _pump(tester, repo, e.value);
        await _tap(tester, 'report-remove-target-1');
        expect(
          find.textContaining('deletes this update permanently'),
          findsOneWidget,
        );
        await _tap(tester, 'confirm-remove-target');
        expect(repo.deletedUpdates, [8]);
        expect(find.byKey(const Key('report-1')), findsNothing);
        expect(find.byKey(const Key('report-2')), findsNothing);
        expect(find.text('Update removed'), findsOneWidget);
      });

      testWidgets('failure keeps reports and shows error', (tester) async {
        final repo = _Fake()
          ..error = ApiException(500, 'internal', 'boom')
          ..items = [_r(1, 'review', 9, rating: 3)];
        await _pump(tester, repo, e.value);
        await _tap(tester, 'report-remove-target-1');
        await _tap(tester, 'confirm-remove-target');
        expect(find.byKey(const Key('report-1')), findsOneWidget);
        expect(find.text('Something went wrong'), findsOneWidget);
        expect(find.text('Review removed'), findsNothing);
      });

      testWidgets('404 counts as success', (tester) async {
        final repo = _Fake()
          ..error = ApiException(404, 'not_found', 'gone')
          ..items = [_r(1, 'review', 9, rating: 3)];
        await _pump(tester, repo, e.value);
        await _tap(tester, 'report-remove-target-1');
        await _tap(tester, 'confirm-remove-target');
        expect(find.byKey(const Key('report-1')), findsNothing);
        expect(find.text('Review removed'), findsOneWidget);
      });

      testWidgets('dismiss all and restore sends target_type review', (
        tester,
      ) async {
        final repo = _Fake()..items = [_r(1, 'review', 9, rating: 3)];
        await _pump(tester, repo, e.value);
        await _tap(tester, 'report-more-1');
        await _tap(tester, 'report-dismiss-all-restore-1');
        await _tap(tester, 'confirm-dismiss-all');
        expect(repo.dismissCalls, [('review', 9, true)]);
        expect(find.byKey(const Key('report-1')), findsNothing);
      });
    });
  }
}
