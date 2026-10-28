import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/admin/admin_screen.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AdminReport _report(
  int id, {
  int spotId = 100,
  String type = 'spot',
  int count = 3,
  String status = 'active',
}) => AdminReport(
  id: id,
  targetType: type,
  targetId: type == 'spot' ? spotId : spotId * 10,
  reason: 'reason-$id',
  createdAt: DateTime.utc(2026, 10, 1, 10),
  reportCount: count,
  reporter: AdminPerson(id: 2, displayName: 'Rita$id', email: 'r$id@x.de'),
  target: AdminReportTarget(
    exists: true,
    spotId: spotId,
    title: 'Spot$spotId',
    status: status,
  ),
);

AdminSpot _spot(
  int id, {
  String status = 'active',
  int reports = 2,
  List<SpotTag> tags = const [],
}) => AdminSpot(
  id: id,
  title: 'Spot$id',
  description: 'Desc$id',
  lat: 48.5,
  lon: 11.25,
  status: status,
  likeCount: 2,
  createdAt: DateTime.utc(2026, 9, 1),
  author: Author(id: 1, displayName: 'Author$id'),
  reportCount: reports,
  tags: tags,
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
  // Repository methods not used by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  List<AdminReport> reportItems = [];
  List<AdminUser> userItems = [for (var i = 1; i <= 3; i++) _user(i)];
  List<AdminSpot> spotItems = [];
  final userPatches = <Map<String, dynamic>>[];
  final spotPatches = <Map<String, dynamic>>[];
  final deletedReports = <int>[];
  final dismissCalls = <(String, int, bool)>[];
  int dismissRemoved = 2;
  ApiException? updateError;
  ApiException? deleteReportError;

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async => AdminPage(reportItems, null);

  @override
  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  }) async => AdminPage(userItems, null);

  @override
  Future<AdminPage<AdminSpot>> spots({
    String? q,
    String? status,
    String? cursor,
    int limit = 20,
  }) async => AdminPage(
    spotItems
        .where((s) => q == null || s.title.contains(q))
        .where((s) => status == null || s.status == status)
        .toList(),
    null,
  );

  @override
  Future<void> deleteSpot(int id) async {}

  @override
  Future<AdminUser> updateUser(int id, AdminUserPatch patch) async {
    userPatches.add(patch.toJson());
    if (updateError != null) throw updateError!;
    final u = userItems.firstWhere((u) => u.id == id);
    return AdminUser(
      id: id,
      email: patch.email ?? u.email,
      displayName: patch.displayName ?? u.displayName,
      isAdmin: patch.isAdmin ?? u.isAdmin,
      createdAt: u.createdAt,
      spotCount: u.spotCount,
      reportsReceived: u.reportsReceived,
    );
  }

  @override
  Future<AdminSpot> updateSpot(int id, AdminSpotPatch patch) async {
    spotPatches.add(patch.toJson());
    if (updateError != null) throw updateError!;
    final s = spotItems.firstWhere((s) => s.id == id);
    return AdminSpot(
      id: id,
      title: patch.title ?? s.title,
      description: patch.description ?? s.description,
      lat: patch.lat ?? s.lat,
      lon: patch.lon ?? s.lon,
      status: patch.status ?? s.status,
      tags: patch.tags ?? s.tags,
      likeCount: s.likeCount,
      createdAt: s.createdAt,
      author: s.author,
      reportCount: s.reportCount,
    );
  }

  @override
  Future<void> deleteReport(int id) async {
    if (deleteReportError != null) throw deleteReportError!;
    deletedReports.add(id);
  }

  @override
  Future<int> dismissReports({
    required String targetType,
    required int targetId,
    required bool restore,
  }) async {
    dismissCalls.add((targetType, targetId, restore));
    return dismissRemoved;
  }

  @override
  Future<void> deleteReview(int id) async {}

  @override
  Future<void> deleteUpdate(int id) async {}
}

class _FakeAuth extends AuthController {
  @override
  Future<User?> build() async => const User(
    id: 1,
    email: 'user1@x.de',
    displayName: 'User1',
    isAdmin: true,
  );
}

Future<void> _pump(WidgetTester tester, _Fake repo, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(_FakeAuth.new),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const AdminScreen()),
            GoRoute(path: '/spot/:id', builder: (_, _) => const Text('SPOT')),
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

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

const _sizes = {
  'phone': Size(400, 800),
  'landscape': Size(844, 390),
  'wide': Size(1100, 700),
};

void main() {
  for (final e in _sizes.entries) {
    group('admin edit ${e.key}', () {
      group('users', () {
        testWidgets('sends only changed fields and updates in place', (
          tester,
        ) async {
          final repo = _Fake();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Users');
          await _tap(tester, 'user-edit-2');
          expect(find.text('Edit user'), findsOneWidget);
          await _type(tester, 'edit-user-name', 'Renamed');
          await _tap(tester, 'edit-user-save');
          expect(repo.userPatches, [
            {'display_name': 'Renamed'},
          ]);
          expect(find.text('Renamed'), findsOneWidget);
          expect(find.text('User2'), findsNothing);
          expect(find.text('User updated'), findsOneWidget);
          expect(find.text('Edit user'), findsNothing);
        });

        testWidgets('email and admin switch are sent when changed', (
          tester,
        ) async {
          final repo = _Fake();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Users');
          await _tap(tester, 'user-edit-2');
          await _type(tester, 'edit-user-email', 'new@x.de');
          await _tap(tester, 'edit-user-admin');
          await _tap(tester, 'edit-user-save');
          expect(repo.userPatches, [
            {'email': 'new@x.de', 'is_admin': true},
          ]);
          expect(find.text('new@x.de'), findsOneWidget);
        });

        testWidgets('unchanged form does not call the API', (tester) async {
          final repo = _Fake();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Users');
          await _tap(tester, 'user-edit-2');
          await _tap(tester, 'edit-user-save');
          expect(repo.userPatches, isEmpty);
          expect(find.text('Edit user'), findsNothing);
        });

        testWidgets('own row: admin switch disabled, name still editable', (
          tester,
        ) async {
          final repo = _Fake();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Users');
          await _tap(tester, 'user-edit-1');
          final sw = tester.widget<Switch>(
            find.descendant(
              of: find.byKey(const Key('edit-user-admin')),
              matching: find.byType(Switch),
            ),
          );
          expect(sw.onChanged, isNull);
          expect(find.textContaining("can't change your own"), findsOneWidget);
          await _type(tester, 'edit-user-name', 'Me');
          await _tap(tester, 'edit-user-save');
          expect(repo.userPatches, [
            {'display_name': 'Me'},
          ]);
        });

        const errors = {
          'invalid_display_name':
              'Invalid display name (1 to 80 characters, no @)',
          'invalid_email': 'Invalid email address',
          'email_taken': 'This email is already in use',
          'cannot_demote_self': "You can't remove your own admin rights",
          'last_admin': 'There must be at least one admin',
          'boom': 'Something went wrong',
        };
        for (final err in errors.entries) {
          testWidgets('error ${err.key} shown inline, dialog stays', (
            tester,
          ) async {
            final repo = _Fake()
              ..updateError = ApiException(
                err.key == 'email_taken' ? 409 : 400,
                err.key,
                'm',
              );
            await _pump(tester, repo, e.value);
            await _tab(tester, 'Users');
            await _tap(tester, 'user-edit-2');
            await _type(tester, 'edit-user-name', 'Zed');
            await _tap(tester, 'edit-user-save');
            expect(find.text('Edit user'), findsOneWidget);
            expect(
              find.descendant(
                of: find.byKey(const Key('edit-user-error')),
                matching: find.text(err.value),
              ),
              findsOneWidget,
            );
            expect(find.text('User2'), findsOneWidget);
            expect(find.text('User updated'), findsNothing);
          });
        }
      });

      group('spots', () {
        _Fake base() => _Fake()
          ..spotItems = [_spot(100), _spot(200)]
          ..reportItems = [_report(1), _report(2, type: 'update')];

        testWidgets('prefilled; only changed fields sent; updates everywhere', (
          tester,
        ) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          expect(find.text('Edit spot'), findsOneWidget);
          expect(find.text('Desc100'), findsOneWidget);
          expect(find.text('48.5, 11.25'), findsOneWidget);
          await _type(tester, 'edit-spot-title', 'Better');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {'title': 'Better'},
          ]);
          expect(find.text('Better'), findsOneWidget);
          expect(find.text('Spot updated'), findsOneWidget);
          await _tab(tester, 'Reports');
          expect(find.text('Better'), findsOneWidget);
          expect(find.text('Update on Better'), findsOneWidget);
          expect(find.text('Spot100'), findsNothing);
        });

        testWidgets('tags are sent only when changed', (tester) async {
          final repo = base()
            ..spotItems = [
              _spot(100, tags: const [SpotTag.roof]),
            ];
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          expect(
            tester
                .widget<FilterChip>(find.byKey(const Key('edit-spot-tag-roof')))
                .selected,
            isTrue,
          );
          // untouched tags: title-only patch carries no tags
          await _type(tester, 'edit-spot-title', 'Better');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {'title': 'Better'},
          ]);
        });

        testWidgets('changed tags are sent as a list', (tester) async {
          final repo = base()
            ..spotItems = [
              _spot(100, tags: const [SpotTag.roof]),
            ];
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          await _tap(tester, 'edit-spot-tag-lit');
          await _tap(tester, 'edit-spot-tag-view');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {
              'tags': ['roof', 'view', 'lit'],
            },
          ]);
        });

        testWidgets('description and status are sent', (tester) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          await _type(tester, 'edit-spot-description', 'New text');
          await _tap(tester, 'edit-spot-status-hidden');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {'description': 'New text', 'status': 'hidden'},
          ]);
          expect(find.text('Hidden'), findsWidgets);
        });

        testWidgets('changed coordinates send lat and lon together', (
          tester,
        ) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          await _type(tester, 'edit-spot-coords', '48.137, 11.575');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {'lat': 48.137, 'lon': 11.575},
          ]);
        });

        testWidgets('unparsable coordinates never call the API', (
          tester,
        ) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          await _type(tester, 'edit-spot-coords', 'nowhere');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, isEmpty);
          expect(find.textContaining('Could not read'), findsOneWidget);
          expect(find.text('Edit spot'), findsOneWidget);
        });

        testWidgets('outside region coordinates never call the API', (
          tester,
        ) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tap(tester, 'spot-edit-100');
          await _type(tester, 'edit-spot-coords', '40.4, -3.7');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, isEmpty);
          expect(find.textContaining('outside the supported'), findsOneWidget);
        });

        const errors = {
          'invalid_title': 'Invalid title',
          'invalid_description': 'Invalid description',
          'invalid_category': 'Invalid category',
          'invalid_status': 'Invalid status',
          'invalid_location': 'Invalid location',
          'boom': 'Something went wrong',
        };
        for (final err in errors.entries) {
          testWidgets('error ${err.key} shown inline, dialog stays', (
            tester,
          ) async {
            final repo = base()..updateError = ApiException(400, err.key, 'm');
            await _pump(tester, repo, e.value);
            await _tab(tester, 'Spots');
            await _tap(tester, 'spot-edit-100');
            await _type(tester, 'edit-spot-title', 'Zed');
            await _tap(tester, 'edit-spot-save');
            expect(find.text('Edit spot'), findsOneWidget);
            expect(
              find.descendant(
                of: find.byKey(const Key('edit-spot-error')),
                matching: find.text(err.value),
              ),
              findsOneWidget,
            );
            expect(find.text('Spot updated'), findsNothing);
          });
        }

        testWidgets('report tile "Edit spot" opens the dialog even when the '
            'spot list was never loaded', (tester) async {
          final repo = base();
          await _pump(tester, repo, e.value);
          await _tap(tester, 'report-edit-spot-1');
          expect(find.text('Desc100'), findsOneWidget);
          await _type(tester, 'edit-spot-title', 'FromReport');
          await _tap(tester, 'edit-spot-save');
          expect(repo.spotPatches, [
            {'title': 'FromReport'},
          ]);
          expect(find.text('FromReport'), findsOneWidget);
          expect(find.text('Update on FromReport'), findsOneWidget);
        });
      });

      group('dismiss reports', () {
        testWidgets('single dismiss removes it and decrements the count', (
          tester,
        ) async {
          final repo = _Fake()
            ..reportItems = [
              _report(1, count: 3),
              _report(3, count: 3),
              _report(5, spotId: 300, count: 1),
            ];
          await _pump(tester, repo, e.value);
          await _tap(tester, 'report-dismiss-1');
          expect(repo.deletedReports, [1]);
          expect(find.byKey(const Key('report-1')), findsNothing);
          expect(find.text('Report dismissed'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byKey(const Key('report-3')),
              matching: find.text('2 reports'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('report-5')),
              matching: find.text('1 report'),
            ),
            findsOneWidget,
          );
        });

        testWidgets('dismiss 404 counts as removed', (tester) async {
          final repo = _Fake()
            ..reportItems = [_report(1)]
            ..deleteReportError = ApiException(404, 'not_found', 'x');
          await _pump(tester, repo, e.value);
          await _tap(tester, 'report-dismiss-1');
          expect(find.byKey(const Key('report-1')), findsNothing);
        });

        testWidgets('dismiss failure keeps the report', (tester) async {
          final repo = _Fake()
            ..reportItems = [_report(1)]
            ..deleteReportError = ApiException(500, 'internal', 'x');
          await _pump(tester, repo, e.value);
          await _tap(tester, 'report-dismiss-1');
          expect(find.byKey(const Key('report-1')), findsOneWidget);
          expect(find.text('Something went wrong'), findsOneWidget);
        });

        testWidgets('dismiss all and restore reactivates the spot', (
          tester,
        ) async {
          final repo = _Fake()
            ..reportItems = [
              _report(1, status: 'hidden'),
              _report(3, status: 'hidden'),
              _report(5, spotId: 300),
            ]
            ..spotItems = [_spot(100, status: 'hidden', reports: 3)];
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots'); // load spots list
          await _tab(tester, 'Reports');
          await _tap(tester, 'report-more-1');
          await tester.tap(
            find.byKey(const Key('report-dismiss-all-restore-1')),
          );
          await tester.pumpAndSettle();
          expect(repo.dismissCalls, isEmpty); // confirm first
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(repo.dismissCalls, isEmpty);
          await _tap(tester, 'report-more-1');
          await tester.tap(
            find.byKey(const Key('report-dismiss-all-restore-1')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-dismiss-all')));
          await tester.pumpAndSettle();
          expect(repo.dismissCalls, [('spot', 100, true)]);
          expect(find.byKey(const Key('report-1')), findsNothing);
          expect(find.byKey(const Key('report-3')), findsNothing);
          expect(find.byKey(const Key('report-5')), findsOneWidget);
          expect(find.text('2 reports dismissed'), findsOneWidget);
          await _tab(tester, 'Spots');
          expect(
            find.descendant(
              of: find.byKey(const Key('spot-100')),
              matching: find.text('Active'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const Key('spot-100')),
              matching: find.textContaining('1 report'),
            ),
            findsOneWidget,
          );
        });

        testWidgets('dismiss all keep hidden leaves the spot hidden', (
          tester,
        ) async {
          final repo = _Fake()
            ..reportItems = [
              _report(1, status: 'hidden'),
              _report(3, status: 'hidden'),
            ]
            ..spotItems = [_spot(100, status: 'hidden')];
          await _pump(tester, repo, e.value);
          await _tab(tester, 'Spots');
          await _tab(tester, 'Reports');
          await _tap(tester, 'report-more-1');
          await tester.tap(find.byKey(const Key('report-dismiss-all-keep-1')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-dismiss-all')));
          await tester.pumpAndSettle();
          expect(repo.dismissCalls, [('spot', 100, false)]);
          expect(find.byKey(const Key('report-1')), findsNothing);
          await _tab(tester, 'Spots');
          expect(
            find.descendant(
              of: find.byKey(const Key('spot-100')),
              matching: find.text('Hidden'),
            ),
            findsOneWidget,
          );
        });
      });
    });
  }
}
