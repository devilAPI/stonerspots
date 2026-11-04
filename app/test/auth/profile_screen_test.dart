import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/profile_screen.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../users/users_helpers.dart';

class _Repo implements AuthRepository {
  ApiException? failWith;
  String? changedNext;
  String? deletedWith;
  User user = const User(id: 1, email: 'a@b.ch', displayName: 'Alex');

  @override
  Future<AuthSession> login(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required bool adult,
  }) => throw UnimplementedError();
  @override
  Future<User?> me() async => user;
  @override
  Future<AuthSession> changePassword({
    required String current,
    required String next,
  }) async {
    if (failWith != null) throw failWith!;
    changedNext = next;
    return AuthSession(
      user: user,
      tokens: const Tokens(accessToken: 'n1', refreshToken: 'n2'),
    );
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    if (failWith != null) throw failWith!;
    deletedWith = password;
  }
}

Future<(_Repo, TokenStore)> _pump(
  WidgetTester tester, {
  bool auth = true,
  User? user,
}) async {
  final repo = _Repo();
  if (user != null) repo.user = user;
  final store = TokenStore.memory();
  if (auth) {
    await store.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
  }
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(store),
        usersRepositoryProvider.overrideWithValue(
          FakeUsers(
            profiles: {
              1: UserProfile(
                id: 1,
                displayName: 'Alex',
                createdAt: DateTime.utc(2025),
                isMe: true,
              ),
              2: UserProfile(
                id: 2,
                displayName: 'Root',
                createdAt: DateTime.utc(2025),
                isMe: true,
              ),
            },
          ),
        ),
      ],
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
            GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
            GoRoute(path: '/admin', builder: (_, _) => const Text('ADMIN')),
            GoRoute(path: '/saved', builder: (_, _) => const Text('SAVED')),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (repo, store);
}

/// Opens the account menu, and picks [item] from it if given.
Future<void> _menu(WidgetTester tester, [String? item]) async {
  await tester.tap(find.byKey(const Key('account-menu')));
  await tester.pumpAndSettle();
  if (item == null) return;
  await tester.tap(find.byKey(Key(item)));
  await tester.pumpAndSettle();
}

Future<void> _fillPasswords(
  WidgetTester tester, {
  String current = 'old',
  String next = 'newpassword1',
  String? repeat,
}) async {
  await tester.enterText(find.byKey(const Key('current-password')), current);
  await tester.enterText(find.byKey(const Key('new-password')), next);
  await tester.enterText(
    find.byKey(const Key('repeat-password')),
    repeat ?? next,
  );
  await tester.tap(find.byKey(const Key('change-password-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the profile page, email in the account menu', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byKey(const Key('userName')), findsOneWidget);
    expect(find.text('Alex'), findsWidgets);
    expect(find.byKey(const Key('statFollowers')), findsOneWidget);
    expect(find.byKey(const Key('followButton')), findsNothing);
    await _menu(tester);
    expect(find.text('a@b.ch'), findsOneWidget);
  });

  testWidgets('log out from the account menu', (tester) async {
    final (_, store) = await _pump(tester);
    await _menu(tester, 'logout');
    expect(await store.read(), isNull);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('anonymous sees only login', (tester) async {
    await _pump(tester, auth: false);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.byKey(const Key('change-password')), findsNothing);
    expect(find.byKey(const Key('delete-account')), findsNothing);
  });

  testWidgets('a logged-in user can open their saved spots', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('open-saved')));
    await tester.pumpAndSettle();
    expect(find.text('SAVED'), findsOneWidget);
  });

  testWidgets('anonymous has no saved entry', (tester) async {
    await _pump(tester, auth: false);
    expect(find.byKey(const Key('open-saved')), findsNothing);
  });

  testWidgets('normal user does not see the Admin button', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('open-admin')), findsNothing);
  });

  testWidgets('admin sees the Admin button and it opens /admin', (
    tester,
  ) async {
    await _pump(
      tester,
      user: const User(
        id: 2,
        email: 'r@b.ch',
        displayName: 'Root',
        isAdmin: true,
      ),
    );
    expect(find.byKey(const Key('open-admin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-admin')));
    await tester.pumpAndSettle();
    expect(find.text('ADMIN'), findsOneWidget);
  });

  testWidgets('change password validates, succeeds, keeps session', (
    tester,
  ) async {
    final (repo, store) = await _pump(tester);
    await _menu(tester, 'change-password');

    await _fillPasswords(tester, next: 'short', repeat: 'other');
    expect(repo.changedNext, isNull);
    expect(find.text('At least 10 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);

    await _fillPasswords(tester);
    expect(repo.changedNext, 'newpassword1');
    expect(find.byKey(const Key('new-password')), findsNothing);
    expect(find.text('Password changed'), findsOneWidget);
    expect((await store.read())?.accessToken, 'n1');
    expect(find.text('Alex'), findsWidgets);
  });

  testWidgets('change password rejects more than 72 characters', (
    tester,
  ) async {
    final (repo, _) = await _pump(tester);
    await _menu(tester, 'change-password');
    await _fillPasswords(tester, next: 'a' * 73);
    expect(repo.changedNext, isNull);
    expect(find.text('At most 72 characters'), findsOneWidget);
  });

  testWidgets('wrong current password shows inline error', (tester) async {
    final (repo, _) = await _pump(tester);
    repo.failWith = ApiException(403, 'wrong_password', 'x');
    await _menu(tester, 'change-password');
    await _fillPasswords(tester, current: 'bad');
    expect(find.text('Wrong password'), findsOneWidget);
    expect(find.byKey(const Key('new-password')), findsOneWidget);
  });

  testWidgets('delete account requires password and logs out', (tester) async {
    final (repo, store) = await _pump(tester);
    await _menu(tester, 'delete-account');

    await tester.tap(find.byKey(const Key('delete-account-submit')));
    await tester.pumpAndSettle();
    expect(repo.deletedWith, isNull);
    expect(find.text('Required'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('delete-password')), 'pw');
    await tester.tap(find.byKey(const Key('delete-account-submit')));
    await tester.pumpAndSettle();

    expect(repo.deletedWith, 'pw');
    expect(await store.read(), isNull);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('delete account wrong password shows inline error', (
    tester,
  ) async {
    final (repo, store) = await _pump(tester);
    repo.failWith = ApiException(403, 'wrong_password', 'x');
    await _menu(tester, 'delete-account');
    await tester.enterText(find.byKey(const Key('delete-password')), 'bad');
    await tester.tap(find.byKey(const Key('delete-account-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong password'), findsOneWidget);
    expect(await store.read(), isNotNull);
  });
}
