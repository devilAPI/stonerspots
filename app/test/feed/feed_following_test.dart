import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/feed/feed_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements FeedRepository {
  final following = <bool>[];

  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
    List<SpotTag> tags = const [],
    bool following = false,
    int? radiusKm,
  }) async {
    this.following.add(following);
    return const FeedPage([], null);
  }
}

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;

  void set(User? u) => state = AsyncData(u);
}

const _me = User(id: 1, email: 'a@b.de', displayName: 'Me');

Future<_Auth> _pump(
  WidgetTester t,
  _Repo repo, {
  User? user,
  Locale locale = const Locale('en'),
}) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final auth = _Auth(user);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        feedRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => auth),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const FeedScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
  return auth;
}

Future<void> openFilters(WidgetTester t) async {
  await t.tap(find.byKey(const Key('feedFilters')));
  await t.pumpAndSettle();
}

Future<void> closeFilters(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('feedFiltersDone')));
  await t.tap(find.byKey(const Key('feedFiltersDone')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('no Following filter when logged out', (t) async {
    await _pump(t, _Repo());
    await openFilters(t);
    expect(find.byKey(const Key('feedFollowing')), findsNothing);
  });

  testWidgets('Following filters the feed and says when it is empty', (
    t,
  ) async {
    final repo = _Repo();
    await _pump(t, repo, user: _me);
    expect(repo.following.last, isFalse);
    await openFilters(t);
    final toggle = find.byKey(const Key('feedFollowing'));
    expect(toggle, findsOneWidget);
    expect(find.text('Only people I follow'), findsOneWidget);

    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(repo.following.last, isTrue);
    expect(t.widget<SwitchListTile>(toggle).value, isTrue);
    await closeFilters(t);
    expect(find.text('No updates from people you follow yet'), findsOneWidget);
    expect(find.byKey(const Key('feedActive-following')), findsOneWidget);

    await openFilters(t);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(repo.following.last, isFalse);
    expect(t.widget<SwitchListTile>(toggle).value, isFalse);
  });

  testWidgets('logging out turns the filter off', (t) async {
    final repo = _Repo();
    final auth = await _pump(t, repo, user: _me);
    await openFilters(t);
    await t.tap(find.byKey(const Key('feedFollowing')));
    await t.pumpAndSettle();
    await closeFilters(t);
    expect(repo.following.last, isTrue);

    auth.set(null);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feedActive-following')), findsNothing);
    expect(repo.following.last, isFalse);
  });

  testWidgets('German label', (t) async {
    await _pump(t, _Repo(), user: _me, locale: const Locale('de'));
    await openFilters(t);
    expect(find.text('Nur Leute, denen ich folge'), findsOneWidget);
  });
}
