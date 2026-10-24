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

AdminReport _report(int id, {int spotId = 100, bool exists = true}) =>
    AdminReport(
      id: id,
      targetType: id % 2 == 0 ? 'update' : 'spot',
      targetId: spotId,
      reason: 'reason-$id',
      createdAt: DateTime.utc(2026, 10, 1, 10),
      reportCount: 3,
      reporter: AdminPerson(
        id: 2,
        displayName: 'Rita$id',
        email: 'rita$id@x.de',
      ),
      target: exists
          ? AdminReportTarget(
              exists: true,
              spotId: spotId,
              title: 'Spot$spotId',
              status: 'active',
              body: id % 2 == 0 ? 'update-text-$id' : '',
            )
          : const AdminReportTarget(exists: false),
    );

AdminSpot _spot(int id, {String status = 'active'}) => AdminSpot(
  id: id,
  title: 'Spot$id',
  lat: 48,
  lon: 11,
  status: status,
  likeCount: 2,
  createdAt: DateTime.utc(2026, 9, 1),
  author: Author(id: 1, displayName: 'Author$id'),
  reportCount: 1,
);

AdminUser _user(int id) => AdminUser(
  id: id,
  email: 'user$id@x.de',
  displayName: 'User$id',
  isAdmin: id == 1,
  createdAt: DateTime.utc(2026, 1, 2),
  spotCount: 4,
  reportsReceived: 2,
);

class _Fake implements AdminRepository {
  // New repository methods are not used by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  _Fake({this.pageSize = 3});
  final int pageSize;
  List<AdminReport> reportItems = [];
  List<AdminUser> userItems = [for (var i = 1; i <= 8; i++) _user(i)];
  List<AdminSpot> spotItems = [];
  final reportCursors = <String?>[];
  final userCalls = <String?>[];
  final spotCalls = <(String?, String?)>[];
  final deleted = <int>[];
  ApiException? deleteError;

  AdminPage<T> _page<T>(List<T> all, String? cursor) {
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + pageSize).clamp(0, all.length);
    return AdminPage(all.sublist(start, end), end < all.length ? '$end' : null);
  }

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async {
    reportCursors.add(cursor);
    return _page(reportItems, cursor);
  }

  @override
  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  }) async {
    userCalls.add(q);
    final f = userItems
        .where((u) => q == null || u.displayName.contains(q))
        .toList();
    return _page(f, cursor);
  }

  @override
  Future<AdminPage<AdminSpot>> spots({
    String? q,
    String? status,
    String? cursor,
    int limit = 20,
  }) async {
    spotCalls.add((q, status));
    final f = spotItems
        .where((s) => status == null || s.status == status)
        .toList();
    return _page(f, cursor);
  }

  @override
  Future<void> deleteSpot(int id) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(id);
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

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

const _sizes = {'phone': Size(400, 800), 'wide': Size(1100, 700)};

void main() {
  for (final e in _sizes.entries) {
    group('AdminScreen ${e.key}', () {
      testWidgets('tabs render and reports show details', (tester) async {
        final repo = _Fake()
          ..reportItems = [_report(1), _report(2), _report(3, exists: false)];
        await _pump(tester, repo, e.value);
        expect(find.text('Reports'), findsOneWidget);
        expect(find.text('Users'), findsOneWidget);
        expect(find.text('Spots'), findsOneWidget);
        expect(find.text('reason-1'), findsOneWidget);
        expect(find.text('3 reports'), findsWidgets);
        expect(find.textContaining('Rita1'), findsOneWidget);
        expect(find.textContaining('rita1@x.de'), findsOneWidget);
        expect(find.textContaining('Spot100'), findsWidgets);
        expect(find.textContaining('update-text-2'), findsOneWidget);
        expect(find.text('Active'), findsWidgets);
      });

      testWidgets('report with missing target shows deleted, no actions', (
        tester,
      ) async {
        final repo = _Fake()..reportItems = [_report(3, exists: false)];
        await _pump(tester, repo, e.value);
        expect(find.text('Deleted'), findsOneWidget);
        expect(find.byKey(const Key('report-open-3')), findsNothing);
        expect(find.byKey(const Key('report-remove-3')), findsNothing);
      });

      testWidgets('open spot pushes the spot route', (tester) async {
        final repo = _Fake()..reportItems = [_report(1)];
        await _pump(tester, repo, e.value);
        await tester.tap(find.byKey(const Key('report-open-1')));
        await tester.pumpAndSettle();
        expect(find.text('SPOT 100'), findsOneWidget);
      });

      testWidgets('empty reports show the empty state', (tester) async {
        await _pump(tester, _Fake(), e.value);
        expect(find.text('Nothing found'), findsOneWidget);
      });

      testWidgets('load more appends next page without duplicates', (
        tester,
      ) async {
        final repo = _Fake(pageSize: 4)
          ..reportItems = [for (var i = 1; i <= 10; i++) _report(i, spotId: i)];
        await _pump(tester, repo, e.value);
        await tester.scrollUntilVisible(
          find.byKey(const Key('report-10')),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        expect(repo.reportCursors, [null, '4', '8']);
        expect(find.byKey(const Key('report-10')), findsOneWidget);
      });

      testWidgets('user search calls repository only on submit', (
        tester,
      ) async {
        final repo = _Fake(pageSize: 20);
        await _pump(tester, repo, e.value);
        await _tab(tester, 'Users');
        expect(repo.userCalls, [null]);
        expect(find.text('User1'), findsOneWidget);
        expect(find.text('admin'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('users-search')), 'User');
        await tester.enterText(find.byKey(const Key('users-search')), 'User5');
        await tester.pump();
        expect(repo.userCalls, [null]);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(repo.userCalls, [null, 'User5']);
        expect(find.byKey(const Key('user-5')), findsOneWidget);
        expect(find.text('User2'), findsNothing);
      });

      testWidgets('spot status filter passes status', (tester) async {
        final repo = _Fake()
          ..spotItems = [_spot(1), _spot(2, status: 'hidden')];
        await _pump(tester, repo, e.value);
        await _tab(tester, 'Spots');
        expect(repo.spotCalls.last, (null, null));
        await tester.tap(find.byKey(const Key('spots-filter-hidden')));
        await tester.pumpAndSettle();
        expect(repo.spotCalls.last, (null, 'hidden'));
        expect(find.text('Spot2'), findsOneWidget);
        expect(find.text('Spot1'), findsNothing);
      });

      testWidgets('removing a spot updates both lists and shows snackbar', (
        tester,
      ) async {
        final repo = _Fake()
          ..reportItems = [_report(1), _report(2, spotId: 200)]
          ..spotItems = [_spot(100), _spot(200)];
        await _pump(tester, repo, e.value);
        await _tab(tester, 'Spots');
        await tester.tap(find.byKey(const Key('spot-remove-100')));
        await tester.pumpAndSettle();
        expect(find.textContaining('permanently'), findsOneWidget);
        await tester.tap(find.byKey(const Key('confirm-remove-spot')));
        await tester.pumpAndSettle();
        expect(repo.deleted, [100]);
        expect(find.byKey(const Key('spot-100')), findsNothing);
        expect(find.byKey(const Key('spot-200')), findsOneWidget);
        expect(find.text('Spot removed'), findsOneWidget);
        await _tab(tester, 'Reports');
        expect(find.byKey(const Key('report-1')), findsNothing);
        expect(find.byKey(const Key('report-2')), findsOneWidget);
      });

      testWidgets('removing from a report works and cancel does nothing', (
        tester,
      ) async {
        final repo = _Fake()
          ..reportItems = [_report(1)]
          ..spotItems = [_spot(100)];
        await _pump(tester, repo, e.value);
        await tester.tap(find.byKey(const Key('report-remove-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repo.deleted, isEmpty);
        expect(find.byKey(const Key('report-1')), findsOneWidget);
        await tester.tap(find.byKey(const Key('report-remove-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-remove-spot')));
        await tester.pumpAndSettle();
        expect(repo.deleted, [100]);
        expect(find.byKey(const Key('report-1')), findsNothing);
      });

      testWidgets('failed delete keeps the item and shows an error', (
        tester,
      ) async {
        final repo = _Fake()
          ..deleteError = ApiException(500, 'internal', 'boom')
          ..spotItems = [_spot(100)];
        await _pump(tester, repo, e.value);
        await _tab(tester, 'Spots');
        await tester.tap(find.byKey(const Key('spot-remove-100')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-remove-spot')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('spot-100')), findsOneWidget);
        expect(find.text('Something went wrong'), findsOneWidget);
        expect(find.text('Spot removed'), findsNothing);
      });

      testWidgets('delete 404 counts as success', (tester) async {
        final repo = _Fake()
          ..deleteError = ApiException(404, 'not_found', 'gone')
          ..spotItems = [_spot(100)];
        await _pump(tester, repo, e.value);
        await _tab(tester, 'Spots');
        await tester.tap(find.byKey(const Key('spot-remove-100')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-remove-spot')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('spot-100')), findsNothing);
      });
    });
  }
}
