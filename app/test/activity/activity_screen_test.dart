import 'package:app/core/models.dart';
import 'package:app/features/activity/activity_bell.dart';
import 'package:app/features/activity/activity_controller.dart';
import 'package:app/features/activity/activity_repository.dart';
import 'package:app/features/activity/activity_screen.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/profile_screen.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../users/users_helpers.dart' show FakeUsers;
import 'activity_helpers.dart';

/// A home page with the bell in its app bar, the activity page and
/// stand-ins for the pages it links to.
Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester t,
  FakeActivity repo, {
  User? user = kMe,
  Locale locale = const Locale('en'),
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(
          appBar: AppBar(
            title: const Text('home page'),
            actions: const [ActivityBell()],
          ),
        ),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const ActivityScreen()),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) =>
            Scaffold(body: Text('user page ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/spot/:id',
        builder: (_, s) =>
            Scaffold(body: Text('spot page ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      activityRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(() => FakeAuth(user)),
    ],
  );
  addTearDown(container.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
  return (router, container);
}

String? _badge(WidgetTester t) {
  final badge = t.widget<Badge>(find.byKey(const Key('activity-badge')));
  return badge.isLabelVisible ? (badge.label! as Text).data : null;
}

void main() {
  testWidgets('the bell shows the unread count when logged in', (t) async {
    final repo = FakeActivity(items: [likeOf(3), followBy(2), followBy(1)]);
    await _pump(t, repo);
    expect(find.byKey(const Key('open-activity')), findsOneWidget);
    expect(_badge(t), '3');
    expect(find.byTooltip('Activity, 3 new'), findsOneWidget);
  });

  testWidgets('no bell when logged out', (t) async {
    final repo = FakeActivity(items: [followBy(1)]);
    await _pump(t, repo, user: null);
    expect(find.byKey(const Key('open-activity')), findsNothing);
    expect(repo.calls, isNot(contains('unread')));
  });

  testWidgets('a large count is capped', (t) async {
    await _pump(t, FakeActivity(unread: 120));
    expect(_badge(t), '99+');
  });

  testWidgets('opening the page lists every kind, highlights the unread '
      'ones and clears the badge', (t) async {
    final repo = FakeActivity(
      items: [
        likeOf(4),
        commentOn(3),
        reviewOf(2, read: true),
        followBy(1, read: true),
      ],
    );
    await _pump(t, repo);
    expect(_badge(t), '2');

    await t.tap(find.byKey(const Key('open-activity')));
    await t.pumpAndSettle();
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Bob liked Bank am See'), findsOneWidget);
    expect(
      find.text('Cleo commented on your spot Aussicht: Schöner Ort'),
      findsOneWidget,
    );
    expect(find.text('Dana rated Wald'), findsOneWidget);
    expect(find.text('Alice started following you'), findsOneWidget);
    expect(find.text('5m'), findsOneWidget);
    expect(find.text('2h'), findsOneWidget);
    // the two that were unread stay highlighted while the page is open
    expect(find.byKey(const Key('activityUnreadDot')), findsNWidgets(2));
    expect(repo.calls, containsAllInOrder(['list:', 'read:4']));

    await t.pageBack();
    await t.pumpAndSettle();
    expect(_badge(t), isNull);
  });

  testWidgets('comments from when they hung under updates keep their text', (
    t,
  ) async {
    final repo = FakeActivity(
      items: [commentOn(2), commentOn(1, oldUpdateId: 5)],
    );
    final (router, _) = await _pump(t, repo, locale: const Locale('de'));
    router.push('/activity');
    await t.pumpAndSettle();
    expect(
      find.text('Cleo hat deinen Spot Aussicht kommentiert: Schöner Ort'),
      findsOneWidget,
    );
    expect(
      find.text('Cleo hat dein Update bei Aussicht kommentiert: Schöner Ort'),
      findsOneWidget,
    );
  });

  testWidgets('a follow opens the profile, anything else the spot', (t) async {
    final repo = FakeActivity(items: [likeOf(2), followBy(1)]);
    final (router, _) = await _pump(t, repo);
    router.push('/activity');
    await t.pumpAndSettle();

    await t.tap(find.text('Alice started following you'));
    await t.pumpAndSettle();
    expect(find.text('user page 7'), findsOneWidget);

    router.pop();
    await t.pumpAndSettle();
    await t.tap(find.text('Bob liked Bank am See'));
    await t.pumpAndSettle();
    expect(find.text('spot page 42'), findsOneWidget);
  });

  testWidgets('nothing yet says so, in German too', (t) async {
    final (router, _) = await _pump(
      t,
      FakeActivity(),
      locale: const Locale('de'),
    );
    router.push('/activity');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('activityEmpty')), findsOneWidget);
    expect(find.text('Aktivität'), findsOneWidget);
  });

  testWidgets('German texts', (t) async {
    final (router, _) = await _pump(
      t,
      FakeActivity(items: [likeOf(4), commentOn(3), reviewOf(2), followBy(1)]),
      locale: const Locale('de'),
    );
    router.push('/activity');
    await t.pumpAndSettle();
    expect(find.text('Alice folgt dir jetzt'), findsOneWidget);
    expect(find.text('Bob gefällt Bank am See'), findsOneWidget);
    expect(
      find.text('Cleo hat deinen Spot Aussicht kommentiert: Schöner Ort'),
      findsOneWidget,
    );
    expect(find.text('Dana hat Wald bewertet'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry and marks nothing', (t) async {
    final repo = FakeActivity(items: [followBy(1)]);
    final (router, _) = await _pump(t, repo);
    repo.fail = Exception('offline');
    router.push('/activity');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('activityError')), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('read:')), isEmpty);

    repo.fail = null;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Alice started following you'), findsOneWidget);
    expect(repo.calls.last, 'read:1');
  });

  testWidgets('pages load as the list scrolls', (t) async {
    final repo = FakeActivity(items: [for (var i = 40; i > 0; i--) followBy(i)])
      ..pageSize = 15;
    final (router, container) = await _pump(t, repo);
    router.push('/activity');
    await t.pumpAndSettle();
    await t.fling(find.byType(ListView), const Offset(0, -3000), 3000);
    await t.pumpAndSettle();
    await t.fling(find.byType(ListView), const Offset(0, -3000), 3000);
    await t.pumpAndSettle();
    expect(container.read(activityFeedProvider).items, hasLength(40));
    expect(repo.calls, containsAll(['list:', 'list:15', 'list:30']));
  });

  testWidgets('the count is asked again on resume and when the profile '
      'shows', (t) async {
    final repo = FakeActivity(unread: 1);
    final shown = ValueNotifier(false);
    addTearDown(shown.dispose);
    final container = ProviderContainer(
      overrides: [
        activityRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => FakeAuth(kMe)),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (_, v, _) => ActivityRefresher(
              profileShown: v,
              child: Scaffold(appBar: AppBar(actions: const [ActivityBell()])),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(_badge(t), '1');
    final before = repo.calls.where((c) => c == 'unread').length;

    repo.unread = 5;
    shown.value = true;
    await t.pumpAndSettle();
    expect(_badge(t), '5');

    repo.unread = 2;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(_badge(t), '2');
    expect(repo.calls.where((c) => c == 'unread').length, before + 2);
  });

  testWidgets('the profile page carries the bell', (t) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(FakeActivity(unread: 2)),
          authControllerProvider.overrideWith(() => FakeAuth(kMe)),
          usersRepositoryProvider.overrideWithValue(
            FakeUsers(
              profiles: {
                1: UserProfile(
                  id: 1,
                  displayName: 'Me',
                  createdAt: DateTime.utc(2025),
                  isMe: true,
                ),
              },
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProfileScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('open-activity')), findsOneWidget);
    expect(_badge(t), '2');
  });

  testWidgets('logging out clears the count', (t) async {
    final repo = FakeActivity(unread: 3);
    final (_, container) = await _pump(t, repo);
    expect(container.read(unreadActivityProvider), 3);
    container.read(authControllerProvider.notifier).state = const AsyncData(
      null,
    );
    await t.pumpAndSettle();
    expect(container.read(unreadActivityProvider), 0);
    expect(find.byKey(const Key('open-activity')), findsNothing);
  });
}
