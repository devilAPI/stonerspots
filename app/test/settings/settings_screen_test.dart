import 'package:app/core/glass.dart';
import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/settings.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/profile_screen.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/features/users/users_repository.dart';

import '../users/users_helpers.dart' show FakeUsers;

const _toggle = Key('disableTransparency');

class _Auth implements AuthRepository {
  @override
  Future<User?> me() async =>
      const User(id: 1, email: 'a@b.ch', displayName: 'Alex');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget page({Locale locale = const Locale('en'), SettingsStore? store}) =>
    ProviderScope(
      overrides: [
        if (store != null) settingsStoreProvider.overrideWithValue(store),
      ],
      child: SettingsScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsScreen(),
        ),
      ),
    );

/// The real router, starting at [location].
Future<ProviderContainer> pumpRouter(
  WidgetTester t,
  String location, {
  bool loggedIn = false,
}) async {
  t.view.physicalSize = const Size(400, 800);
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
      child: SettingsScope(
        child: Consumer(
          builder: (_, ref, _) => MaterialApp.router(
            locale: const Locale('en'),
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
  group('settings page', () {
    testWidgets('the switch shows title and hint, in English', (t) async {
      await t.pumpWidget(page());
      await t.pump();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Disable transparency'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_toggle), matching: find.byType(Switch)),
        findsOneWidget,
      );
    });

    testWidgets('the map and motion switches are kept', (t) async {
      final store = SettingsStore.memory();
      await t.pumpWidget(page(store: store));
      await t.pump();
      for (final (key, setting, before) in [
        ('reduceMotion', 'reduce_motion', false),
        ('buildings3d', 'map_3d_buildings', true),
        ('sharpTiles', 'map_sharp_tiles', true),
      ]) {
        final tile = find.byKey(Key(key));
        await t.scrollUntilVisible(tile, 100);
        expect(t.widget<SwitchListTile>(tile).value, before);
        await t.tap(tile);
        await t.pump();
        expect(store.getBool(setting), !before, reason: key);
        expect(t.widget<SwitchListTile>(tile).value, !before);
      }
    });

    testWidgets('and in German', (t) async {
      await t.pumpWidget(page(locale: const Locale('de')));
      await t.pump();
      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Transparenz deaktivieren'), findsOneWidget);
    });

    testWidgets('the page starts below its glass app bar', (t) async {
      await t.pumpWidget(page());
      await t.pump();
      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(
        t.getTopLeft(find.byKey(_toggle)).dy,
        greaterThan(t.getBottomLeft(find.byType(GlassAppBar)).dy),
      );
    });

    testWidgets('toggling applies at once and is stored', (t) async {
      SharedPreferences.setMockInitialValues({});
      late final SettingsStore store;
      await t.runAsync(() async => store = await SettingsStore.load());
      await t.pumpWidget(page(store: store));
      await t.pump();
      expect(find.byType(LiquidGlass), findsOneWidget); // the app bar

      await t.tap(find.byKey(_toggle));
      await t.pump();
      expect(find.byType(LiquidGlass), findsNothing);
      expect(store.getBool('disable_transparency'), isTrue);
      final prefs = await t.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getBool('disable_transparency'), isTrue);

      await t.tap(find.byKey(_toggle));
      await t.pump();
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets("what's new in 1.0 lists the main features", (t) async {
      await t.pumpWidget(page());
      await t.pump();
      await t.scrollUntilVisible(find.byKey(const Key('whatsNew')), 100);
      await t.ensureVisible(find.byKey(const Key('whatsNew')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('whatsNew')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewDialog')), findsOneWidget);
      expect(find.text("What's new in 1.0"), findsNWidgets(2));
      for (final title in [
        'Map, search & compass',
        'Spots',
        'Feed & Following',
        'Profiles & following',
        'Activity',
        'Saved lists',
        'Admin tools',
        'Automatic updates',
      ]) {
        await t.scrollUntilVisible(
          find.text(title),
          50,
          scrollable: find.descendant(
            of: find.byKey(const Key('whatsNewDialog')),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.textContaining('Ctrl+K'), findsOneWidget);
      expect(find.textContaining('2.0'), findsNothing);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('whatsNewDialog')), findsNothing);
    });

    testWidgets("what's new, in German", (t) async {
      await t.pumpWidget(page(locale: const Locale('de')));
      await t.pump();
      await t.scrollUntilVisible(find.byKey(const Key('whatsNew')), 100);
      await t.ensureVisible(find.byKey(const Key('whatsNew')));
      await t.pumpAndSettle();
      expect(find.text('Über Stonerspots'), findsOneWidget);
      await t.tap(find.byKey(const Key('whatsNew')));
      await t.pumpAndSettle();
      expect(find.text('Neu in 1.0'), findsNWidgets(2));
      expect(find.text('Karte, Suche und Kompass'), findsOneWidget);
      expect(find.textContaining('Strg+K'), findsOneWidget);
      expect(find.text('Schließen'), findsOneWidget);
    });

    testWidgets('a stored setting is on from the very first frame', (t) async {
      SharedPreferences.setMockInitialValues({'disable_transparency': true});
      late final SettingsStore store;
      await t.runAsync(() async => store = await SettingsStore.load());
      await t.pumpWidget(page(store: store));
      expect(find.byType(LiquidGlass), findsNothing);
    });
  });

  group('getting there', () {
    testWidgets('logged out: gear on the profile, back returns', (t) async {
      await pumpRouter(t, '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      await t.tap(find.byKey(const Key('open-settings')));
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      // outside the shell: no tab bar
      expect(find.byType(LoupeTabBar), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('logged in: the gear is there too', (t) async {
      final c = await pumpRouter(t, '/profile', loggedIn: true);
      await t.pumpAndSettle();
      expect(c.read(authControllerProvider).value?.id, 1);
      expect(find.byKey(const Key('userName')), findsOneWidget);
      await t.tap(find.byKey(const Key('open-settings')));
      await t.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('opened directly: the page leads back home', (t) async {
      await pumpRouter(t, '/settings');
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byKey(const Key('backToHome')), findsOneWidget);
    });

    testWidgets('the tab bar is solid after coming back', (t) async {
      await pumpRouter(t, '/profile');
      expect(find.byType(LoupeTabBar), findsOneWidget);
      await t.tap(find.byKey(const Key('open-settings')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(_toggle));
      await t.pump();
      expect(find.byType(LiquidGlass), findsNothing);
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(find.byType(LoupeTabBar), findsNothing);
      expect(find.byType(LiquidGlass), findsNothing);
      expect(find.text('Profile'), findsWidgets);
    });
  });
}
