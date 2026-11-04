import 'package:app/core/settings.dart';
import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/login_screen.dart';
import 'package:app/features/auth/register_screen.dart';
import 'package:app/features/legal/legal_info.dart';
import 'package:app/features/legal/legal_links.dart';
import 'package:app/features/legal/legal_pages.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../users/users_helpers.dart' show FakeUsers;
import 'legal_helpers.dart';

class _Auth implements AuthRepository {
  @override
  Future<User?> me() async =>
      const User(id: 1, email: 'a@b.ch', displayName: 'Alex');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The real router at [location].
Future<ProviderContainer> pumpRouter(
  WidgetTester t,
  String location, {
  bool loggedIn = false,
  String lang = 'en',
}) async {
  t.view.physicalSize = const Size(500, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final tokens = TokenStore.memory();
  if (loggedIn) {
    await tokens.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
  }
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(_Auth()),
      tokenStoreProvider.overrideWithValue(tokens),
      legalRepositoryProvider.overrideWithValue(FakeLegal()),
      usersRepositoryProvider.overrideWithValue(
        FakeUsers(
          profiles: {
            1: UserProfile(
              id: 1,
              displayName: 'Alex',
              createdAt: DateTime.utc(2025),
              isMe: true,
            ),
          },
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(routerProvider).go(location);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: GlassSettingScope(
        child: Consumer(
          builder: (_, ref, _) => MaterialApp.router(
            locale: Locale(lang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

void main() {
  group('deep links, logged out', () {
    for (final (path, page) in [
      (kImprintPath, ImprintScreen),
      (kPrivacyPath, PrivacyScreen),
      (kRulesPath, RulesScreen),
    ]) {
      testWidgets('$path opens without login and leads home', (t) async {
        await pumpRouter(t, path);
        expect(find.byType(page), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(find.byKey(const Key('backToHome')), findsOneWidget);
      });
    }

    testWidgets('logged in too', (t) async {
      await pumpRouter(t, kPrivacyPath, loggedIn: true);
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });
  });

  group('login and registration', () {
    testWidgets('the login page links all three, and back returns', (t) async {
      await pumpRouter(t, '/login');
      expect(find.byKey(const Key('legalLinks')), findsOneWidget);
      expect(find.text('Legal notice'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Community rules'), findsOneWidget);

      await t.tap(find.byKey(const Key('link-privacy')));
      await t.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await t.tap(find.byKey(const Key('link-imprint')));
      await t.pumpAndSettle();
      expect(find.byType(ImprintScreen), findsOneWidget);
    });

    testWidgets('registering: consent sentence with links, one checkbox', (
      t,
    ) async {
      await pumpRouter(t, '/register');
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget); // the 18+ one only
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('By registering you accept the'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('legalLinks')), findsOneWidget);

      await t.tap(find.byKey(const Key('consent-rules')));
      await t.pumpAndSettle();
      expect(find.byType(RulesScreen), findsOneWidget);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();

      await t.tap(find.byKey(const Key('consent-privacy')));
      await t.pumpAndSettle();
      expect(find.byType(PrivacyScreen), findsOneWidget);
    });

    testWidgets('the consent sentence in German', (t) async {
      await pumpRouter(t, '/register', lang: 'de');
      expect(find.text('Nutzungsregeln'), findsNWidgets(2)); // and footer
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().startsWith(
                'Mit der Registrierung akzeptierst du die',
              ),
        ),
        findsOneWidget,
      );
    });

    test('bracket links split', () {
      expect(splitBracketLinks('a [b] c [d] e'), ['a ', 'b', ' c ', 'd', ' e']);
      expect(splitBracketLinks('plain'), ['plain']);
      expect(splitBracketLinks('[x]'), ['', 'x', '']);
    });
  });

  group('settings', () {
    for (final loggedIn in [false, true]) {
      testWidgets('the legal section (logged in: $loggedIn)', (t) async {
        await pumpRouter(t, '/settings', loggedIn: loggedIn);
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('Legal'), findsOneWidget);
        for (final (key, page) in [
          ('settings-imprint', ImprintScreen),
          ('settings-privacy', PrivacyScreen),
          ('settings-rules', RulesScreen),
        ]) {
          await t.scrollUntilVisible(find.byKey(Key(key)), 100);
          await t.tap(find.byKey(Key(key)));
          await t.pumpAndSettle();
          expect(find.byType(page), findsOneWidget, reason: key);
          await t.tap(find.byType(BackButton));
          await t.pumpAndSettle();
          expect(find.byType(SettingsScreen), findsOneWidget);
        }
      });
    }

    testWidgets('in German', (t) async {
      await pumpRouter(t, '/settings', lang: 'de');
      expect(find.text('Rechtliches'), findsOneWidget);
      expect(find.text('Impressum'), findsOneWidget);
      expect(find.text('Datenschutzerklärung'), findsOneWidget);
    });
  });
}
