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

void main() {
  testWidgets('no Following filter when logged out', (t) async {
    await _pump(t, _Repo());
    expect(find.byKey(const Key('feedFollowing')), findsNothing);
  });

  testWidgets('Following filters the feed and says when it is empty', (
    t,
  ) async {
    final repo = _Repo();
    await _pump(t, repo, user: _me);
    expect(repo.following.last, isFalse);
    final chip = find.byKey(const Key('feedFollowing'));
    expect(chip, findsOneWidget);
    expect(find.text('Following'), findsOneWidget);

    await t.tap(chip);
    await t.pumpAndSettle();
    expect(repo.following.last, isTrue);
    expect(t.widget<FilterChip>(chip).selected, isTrue);
    expect(find.text('No updates from people you follow yet'), findsOneWidget);

    await t.tap(chip);
    await t.pumpAndSettle();
    expect(repo.following.last, isFalse);
    expect(t.widget<FilterChip>(chip).selected, isFalse);
  });

  testWidgets('logging out turns the filter off', (t) async {
    final repo = _Repo();
    final auth = await _pump(t, repo, user: _me);
    await t.tap(find.byKey(const Key('feedFollowing')));
    await t.pumpAndSettle();
    expect(repo.following.last, isTrue);

    auth.set(null);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('feedFollowing')), findsNothing);
    expect(repo.following.last, isFalse);
  });

  testWidgets('German label', (t) async {
    await _pump(t, _Repo(), user: _me, locale: const Locale('de'));
    expect(find.text('Folge ich'), findsOneWidget);
  });
}
