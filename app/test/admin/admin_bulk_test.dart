import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_actions.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/admin/admin_screen.dart';
import 'package:app/features/admin/admin_system_tab.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AdminUser _user(int id, {bool admin = false, bool banned = false}) => AdminUser(
  id: id,
  email: 'user$id@x.de',
  displayName: 'User$id',
  isAdmin: admin,
  banned: banned,
  createdAt: DateTime.utc(2026, 1, 2),
  spotCount: 1,
  reportsReceived: 0,
);

AdminSpot _spot(
  int id, {
  String status = 'active',
  bool locked = false,
  List<SpotTag> tags = const [],
}) => AdminSpot(
  id: id,
  title: 'Spot$id',
  lat: 48,
  lon: 11,
  status: status,
  locked: locked,
  tags: tags,
  likeCount: 0,
  createdAt: DateTime.utc(2026, 9, 1),
  author: const Author(id: 1, displayName: 'A'),
  reportCount: 0,
);

class _Lists implements AdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  List<AdminUser> users_ = [];
  List<AdminSpot> spots_ = [];

  @override
  Future<AdminPage<AdminReport>> reports({
    String? cursor,
    int limit = 20,
  }) async => const AdminPage([], null);

  @override
  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  }) async => AdminPage(users_, null);

  @override
  Future<AdminPage<AdminSpot>> spots({
    String? q,
    String? status,
    String? cursor,
    int limit = 20,
  }) async => AdminPage(spots_, null);
}

class _Actions implements AdminActionsRepository {
  final calls = <(String, String, String, String?)>[];
  BulkResult<AdminUser> userResult = const BulkResult();
  BulkResult<AdminSpot> spotResult = const BulkResult();
  Object? error;

  /// Answers of successive system() calls; the last one repeats. An
  /// Exception in it is thrown (the server is away).
  List<Object> systems = [const SystemInfo()];
  int systemCalls = 0;
  SystemInfo? afterRequest;

  @override
  Future<BulkResult<AdminUser>> bulkUsers(List<int> ids, String action) async {
    calls.add(('users', ids.join(','), action, null));
    if (error != null) throw error!;
    return userResult;
  }

  @override
  Future<BulkResult<AdminSpot>> bulkSpots(
    List<int> ids,
    String action, {
    String? tag,
  }) async {
    calls.add(('spots', ids.join(','), action, tag));
    if (error != null) throw error!;
    return spotResult;
  }

  @override
  Future<SystemInfo> system() async {
    final next = systems[systemCalls.clamp(0, systems.length - 1)];
    systemCalls++;
    if (next is Exception) throw next;
    return next as SystemInfo;
  }

  @override
  Future<SystemInfo> requestUpdate(String channel) async {
    calls.add(('update', '', channel, null));
    return afterRequest!;
  }
}

Future<void> _pump(WidgetTester t, _Lists lists, _Actions actions) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(lists),
        adminActionsRepositoryProvider.overrideWithValue(actions),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => const AdminScreen())],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tab(WidgetTester t, String name) async {
  await t.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(name)),
  );
  await t.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

Checkbox _box(WidgetTester t, String key) =>
    t.widget<Checkbox>(find.byKey(Key(key)));

void main() {
  testWidgets('users: select, ban; admins cannot be selected', (t) async {
    final lists = _Lists()
      ..users_ = [_user(1, admin: true), _user(2), _user(3)];
    final actions = _Actions()
      ..userResult = BulkResult(
        items: [_user(2, banned: true), _user(3, banned: true)],
      );
    await _pump(t, lists, actions);
    await _tab(t, 'Users');

    expect(_box(t, 'user-select-1').onChanged, isNull);
    expect(find.byKey(const Key('admin-selection-bar')), findsNothing);
    await _tapKey(t, 'user-select-2');
    expect(find.text('1 selected'), findsOneWidget);
    await _tapKey(t, 'bulk-select-all');
    expect(find.text('2 selected'), findsOneWidget); // not the admin

    await _tapKey(t, 'bulk-ban');
    expect(actions.calls.single, ('users', '2,3', 'ban', null));
    expect(find.byKey(const Key('user-banned-2')), findsOneWidget);
    expect(find.byKey(const Key('user-banned-3')), findsOneWidget);
    expect(find.text('2 changed'), findsOneWidget);
    // done: the selection is cleared
    expect(find.byKey(const Key('admin-selection-bar')), findsNothing);
  });

  testWidgets('users: delete asks first and drops them from the list', (
    t,
  ) async {
    final lists = _Lists()..users_ = [_user(2), _user(3)];
    final actions = _Actions()
      ..userResult = const BulkResult(deleted: [2], skipped: 1);
    await _pump(t, lists, actions);
    await _tab(t, 'Users');
    await _tapKey(t, 'user-select-2');
    await _tapKey(t, 'user-select-3');

    await _tapKey(t, 'bulk-delete');
    expect(find.text('Delete 2 users?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(actions.calls, isEmpty);
    expect(find.text('2 selected'), findsOneWidget); // kept

    await _tapKey(t, 'bulk-delete');
    await _tapKey(t, 'confirm-bulk-delete');
    expect(actions.calls.single.$3, 'delete');
    expect(find.byKey(const Key('user-2')), findsNothing);
    expect(find.byKey(const Key('user-3')), findsOneWidget);
    expect(find.textContaining('1 deleted'), findsOneWidget);
    expect(find.textContaining('1 skipped'), findsOneWidget);
  });

  testWidgets('users: a failed action keeps the selection', (t) async {
    final lists = _Lists()..users_ = [_user(2)];
    final actions = _Actions()..error = Exception('offline');
    await _pump(t, lists, actions);
    await _tab(t, 'Users');
    await _tapKey(t, 'user-select-2');
    await _tapKey(t, 'bulk-unban');
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('spots: hide, and add a tag picked from the catalog', (t) async {
    final lists = _Lists()..spots_ = [_spot(1), _spot(2)];
    final actions = _Actions()
      ..spotResult = BulkResult(
        items: [
          _spot(1, status: 'hidden'),
          _spot(2, status: 'hidden'),
        ],
      );
    await _pump(t, lists, actions);
    await _tab(t, 'Spots');
    await _tapKey(t, 'spot-select-1');
    await _tapKey(t, 'bulk-select-all');
    await _tapKey(t, 'bulk-hide');
    expect(actions.calls.last, ('spots', '1,2', 'hide', null));
    expect(find.text('Hidden'), findsNWidgets(2 + 1)); // chips + filter

    actions.spotResult = BulkResult(
      items: [
        _spot(1, status: 'hidden', tags: const [SpotTag.water]),
      ],
    );
    await _tapKey(t, 'spot-select-1');
    await _tapKey(t, 'bulk-add_tag');
    expect(find.text('Choose a tag'), findsOneWidget);
    await _tapKey(t, 'bulk-tag-water');
    expect(actions.calls.last, ('spots', '1', 'add_tag', 'water'));

    // dismissing the tag picker does nothing
    await _tapKey(t, 'spot-select-2');
    await _tapKey(t, 'bulk-remove_tag');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(actions.calls.length, 2);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('spots: delete removes them after confirming', (t) async {
    final lists = _Lists()..spots_ = [_spot(1), _spot(2)];
    final actions = _Actions()..spotResult = const BulkResult(deleted: [1]);
    await _pump(t, lists, actions);
    await _tab(t, 'Spots');
    await _tapKey(t, 'spot-select-1');
    await _tapKey(t, 'bulk-delete');
    expect(find.text('Delete 1 spot?'), findsOneWidget);
    await _tapKey(t, 'confirm-bulk-delete');
    expect(find.byKey(const Key('spot-1')), findsNothing);
    expect(find.byKey(const Key('spot-2')), findsOneWidget);
  });

  group('actions tab', () {
    const enabled = SystemInfo(version: 'dev-1', updatesEnabled: true);

    FilledButton release(WidgetTester t) =>
        t.widget<FilledButton>(find.byKey(const Key('update-release')));

    testWidgets('updates off: says so and the buttons are disabled', (t) async {
      final actions = _Actions()..systems = [const SystemInfo()];
      await _pump(t, _Lists(), actions);
      await _tab(t, 'Actions');
      expect(find.textContaining('Version unknown'), findsOneWidget);
      expect(find.byKey(const Key('system-updates-disabled')), findsOneWidget);
      expect(release(t).onPressed, isNull);
    });

    testWidgets('update: asks, follows it through the restart, then done', (
      t,
    ) async {
      final actions = _Actions()
        ..systems = [
          enabled,
          const SystemInfo(
            version: 'dev-1',
            updatesEnabled: true,
            update: UpdateStatus(state: UpdateState.running, channel: 'dev'),
          ),
          Exception('restarting'),
          SystemInfo(
            version: 'dev-2',
            updatesEnabled: true,
            update: UpdateStatus(
              state: UpdateState.done,
              channel: 'dev',
              from: 'dev-1',
              to: 'dev-2',
              finishedAt: DateTime.utc(2026, 10, 29, 12),
              log: '==> Updated to dev-2',
            ),
          ),
        ]
        ..afterRequest = const SystemInfo(
          version: 'dev-1',
          updatesEnabled: true,
          update: UpdateStatus(state: UpdateState.pending),
        );
      await _pump(t, _Lists(), actions);
      await _tab(t, 'Actions');
      expect(find.text('Installed: dev-1'), findsOneWidget);

      await _tapKey(t, 'update-dev');
      expect(find.text('Update the backend?'), findsOneWidget);
      expect(find.textContaining('dev build'), findsWidgets);
      await t.tap(find.byKey(const Key('confirm-update')));
      await t.pump();
      await t.pump();
      expect(actions.calls.single, ('update', '', 'dev', null));
      expect(find.textContaining('waiting for the server'), findsOneWidget);
      expect(release(t).onPressed, isNull);

      await t.pump(kUpdatePollInterval);
      await t.pump();
      expect(find.textContaining('Updating'), findsOneWidget);
      await t.pump(kUpdatePollInterval);
      await t.pump();
      expect(find.text('Server is restarting…'), findsOneWidget);
      await t.pump(kUpdatePollInterval);
      await t.pumpAndSettle();
      expect(find.text('Updated: dev-1 → dev-2'), findsOneWidget);
      expect(find.text('Installed: dev-2'), findsOneWidget);
      expect(release(t).onPressed, isNotNull);

      // and then it stops asking
      final calls = actions.systemCalls;
      await t.pump(kUpdatePollInterval * 3);
      expect(actions.systemCalls, calls);
    });

    testWidgets('a failed update shows its log', (t) async {
      final actions = _Actions()
        ..systems = [
          const SystemInfo(
            version: 'dev-1',
            updatesEnabled: true,
            update: UpdateStatus(
              state: UpdateState.failed,
              from: 'dev-1',
              to: 'dev-1',
              log: 'error: checksum does not match',
            ),
          ),
        ];
      await _pump(t, _Lists(), actions);
      await _tab(t, 'Actions');
      expect(find.textContaining('last update failed'), findsOneWidget);
      expect(find.text('error: checksum does not match'), findsOneWidget);
    });
  });
}
