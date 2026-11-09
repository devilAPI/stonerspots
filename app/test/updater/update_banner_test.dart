import 'package:app/core/settings.dart';
import 'package:app/features/settings/settings_screen.dart';
import 'package:app/features/updater/installer.dart';
import 'package:app/features/updater/release.dart';
import 'package:app/features/updater/update_controller.dart';
import 'package:app/features/updater/update_ui.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'updater_harness.dart';

Widget app(UpdaterHarness h, {Locale locale = const Locale('en')}) =>
    ProviderScope(
      overrides: h.overrides,
      child: GlassSettingScope(
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) => UpdateBannerHost(child: child!),
          home: const Scaffold(body: Center(child: Text('map'))),
        ),
      ),
    );

/// Lets the start-up check (fake HTTP, real futures) finish.
Future<void> settle(WidgetTester t, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await t.pump(const Duration(milliseconds: 10));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await t.pump();
}

void main() {
  testWidgets('a newer build shows a banner over the app', (t) async {
    final h = UpdaterHarness();
    await t.pumpWidget(app(h));
    await settle(t);
    expect(find.text('Update available (dev-7)'), findsOneWidget);
    expect(find.text('Installed: dev-6'), findsOneWidget);
    expect(find.text('map'), findsOneWidget); // the app is still there
    expect(find.byKey(const Key('updateNow')), findsOneWidget);
    expect(find.byKey(const Key('updateLater')), findsOneWidget);
    expect(find.byKey(const Key('updateSkip')), findsOneWidget);
  });

  testWidgets('German', (t) async {
    await t.pumpWidget(app(UpdaterHarness(), locale: const Locale('de')));
    await settle(t);
    expect(find.text('Update verfügbar (dev-7)'), findsOneWidget);
    expect(find.text('Jetzt aktualisieren'), findsOneWidget);
    expect(find.text('Diese Version überspringen'), findsOneWidget);
  });

  testWidgets('Later hides it; Skip keeps it away', (t) async {
    final h = UpdaterHarness();
    await t.pumpWidget(app(h));
    await settle(t);
    await t.tap(find.byKey(const Key('updateLater')));
    await t.pump();
    expect(find.byKey(const Key('updateBanner')), findsNothing);
    expect(h.store.getString('updater.skipped_tag'), isNull);

    await t.pumpWidget(const SizedBox()); // a fresh start
    await t.pumpWidget(app(h));
    await settle(t);
    await t.tap(find.byKey(const Key('updateSkip')));
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    await t.pump();
    expect(find.byKey(const Key('updateBanner')), findsNothing);
    expect(h.store.getString('updater.skipped_tag'), 'dev-7');
  });

  testWidgets('no banner when up to date', (t) async {
    await t.pumpWidget(app(UpdaterHarness(build: '7')));
    await settle(t);
    expect(find.byKey(const Key('updateBanner')), findsNothing);
  });

  testWidgets('without a key: a hint and the release page button', (t) async {
    final h = UpdaterHarness(withKey: false);
    await t.pumpWidget(app(h));
    await settle(t);
    expect(find.textContaining("can't verify updates"), findsOneWidget);
    expect(find.byKey(const Key('updateNow')), findsNothing);
    await t.tap(find.byKey(const Key('updateOpenPage')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(h.opened.single.host, 'github.com');
    expect(h.installer.installed, isEmpty);
  });

  testWidgets('a bad signature is reported, nothing installed', (t) async {
    final h = UpdaterHarness(signature: 'SHA256SUMS-apps.other-key.sig');
    await t.pumpWidget(app(h));
    await settle(t);
    await t.tap(find.byKey(const Key('updateNow')));
    await settle(t);
    expect(find.textContaining('signature'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(h.installer.installed, isEmpty);
  });

  testWidgets('Android without permission: a button to the setting', (t) async {
    final h = UpdaterHarness(platform: UpdatePlatform.android);
    h.installer.block = InstallBlocker.needsInstallPermission;
    await t.pumpWidget(app(h));
    await settle(t);
    await t.tap(find.byKey(const Key('updateNow')));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await t.pump();
    expect(
      find.textContaining('Allow Stonerspots to install apps'),
      findsOneWidget,
    );
    await t.tap(find.byKey(const Key('updateOpenSettings')));
    await t.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(h.installer.permissionScreens, 1);
  });

  testWidgets('a download shows its progress and can be cancelled', (t) async {
    final h = UpdaterHarness();
    h.adapter.routes['$dl/stonerspots-dev-7-linux-x64.tar.gz'] = (_) =>
        FakeResponse(200, text: 'x' * 1000, chunkSize: 10);
    var paused = false;
    h.adapter.onChunk = (sent) => paused = sent >= 500;
    await t.pumpWidget(app(h));
    await settle(t);
    await t.tap(find.byKey(const Key('updateNow')));
    // fake time only: the fake server sends a chunk per tick, so the
    // download stands still half way until the next pump
    for (var i = 0; i < 500 && !paused; i++) {
      await t.pump(const Duration(milliseconds: 1));
    }
    expect(paused, isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Downloading'), findsOneWidget);
    await t.tap(find.byKey(const Key('updateCancel')));
    // file writes are real IO: give them real turns of the event loop
    await settle(t, rounds: 200);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const Key('updateNow')), findsOneWidget);
    expect(h.installer.installed, isEmpty);
  });

  testWidgets('settings: switch and manual check', (t) async {
    final h = UpdaterHarness(build: '7');
    await t.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    expect(find.text('Check for updates automatically'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoUpdateCheck')));
    await t.pump();
    expect(h.store.getBool('auto_update_check'), isFalse);

    await t.tap(find.byKey(const Key('checkUpdates')));
    await settle(t);
    expect(find.text('Up to date (dev-7)'), findsOneWidget);
  });

  Future<void> pumpSettings(WidgetTester t, UpdaterHarness h) => t.pumpWidget(
    ProviderScope(
      overrides: h.overrides,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(),
      ),
    ),
  );

  testWidgets('settings: switching to stable offers the stable release', (
    t,
  ) async {
    // dev build 63 of 1.0.1: up to date on dev
    final h = UpdaterHarness(build: '63', version: '1.0.1');
    await pumpSettings(t, h);
    final tile = find.byKey(const Key('updateChannel'));
    await t.ensureVisible(tile);
    expect(find.text('Update channel'), findsOneWidget);
    await t.tap(find.descendant(of: tile, matching: find.text('Stable')));
    await settle(t);
    expect(h.store.getString('update_channel'), 'release');
    expect(find.textContaining('v1.0.1'), findsWidgets);
  });

  testWidgets('Android, dev build switched to stable: the downgrade note', (
    t,
  ) async {
    final h = UpdaterHarness(platform: UpdatePlatform.android, build: '63');
    h.store.setString('update_channel', 'release');
    await pumpSettings(t, h);
    expect(find.textContaining('uninstall the app first'), findsOneWidget);
  });

  testWidgets('settings on a build without a channel', (t) async {
    final h = UpdaterHarness()..channel = null;
    await t.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    expect(find.text("This build doesn't check for updates."), findsOneWidget);
    expect(find.byKey(const Key('autoUpdateCheck')), findsNothing);
  });

  testWidgets('no update section, no check on iOS / web', (t) async {
    final h = UpdaterHarness(platform: null);
    await t.pumpWidget(
      ProviderScope(
        overrides: h.overrides,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    expect(find.text('Updates'), findsNothing);
    expect(find.byKey(const Key('checkUpdates')), findsNothing);
    await t.pumpWidget(app(h));
    await settle(t);
    expect(h.requested, isEmpty);
  });

  test('which platforms update themselves', () {
    expect(
      const UpdaterConfig(
        channel: UpdateChannel.dev,
        platform: null,
        signingKey: null,
      ).enabled,
      isFalse,
    );
  });
}
