import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repo implements AuthRepository {
  final logins = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<User?> me() async => null;

  @override
  Future<AuthSession> login(String email, String password) async {
    logins.add('$email:$password');
    return const AuthSession(
      user: User(id: 1, email: 'a@b.ch', displayName: 'Alex'),
      tokens: Tokens(accessToken: 'a', refreshToken: 'r'),
    );
  }
}

void main() {
  testWidgets('Enter in the password field logs in', (t) async {
    final repo = _Repo();
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home map')),
        ),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repo),
          tokenStoreProvider.overrideWithValue(TokenStore.memory()),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.enterText(find.byKey(const Key('loginEmail')), 'a@b.ch');
    // Enter in the email field moves on, it does not submit yet
    await t.testTextInput.receiveAction(TextInputAction.next);
    await t.pumpAndSettle();
    expect(repo.logins, isEmpty);

    await t.enterText(find.byKey(const Key('loginPassword')), 'secret-pw');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(repo.logins, ['a@b.ch:secret-pw']);
    expect(find.text('home map'), findsOneWidget);
  });
}
