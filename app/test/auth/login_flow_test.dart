import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  User? user;

  @override
  Future<User?> me() async => user;

  @override
  Future<AuthSession> login(String login, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    user = const User(id: 1, email: 'a@b.ch', displayName: 'Alex');
    return AuthSession(
      user: user!,
      tokens: const Tokens(accessToken: 'a', refreshToken: 'r'),
    );
  }
}

void main() {
  testWidgets('the login page closes after logging in (real router)', (
    t,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Repo()),
        tokenStoreProvider.overrideWithValue(TokenStore.memory()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    router.go('/profile');
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await t.pumpAndSettle();
    router.push('/login');
    await t.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await t.enterText(find.byKey(const Key('loginEmail')), 'a@b.ch');
    await t.enterText(find.byKey(const Key('loginPassword')), 'secret-pw');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 200));
    await t.pumpAndSettle();
    expect(container.read(authControllerProvider).value, isNotNull);
    expect(find.byType(LoginScreen), findsNothing);
  });
}
