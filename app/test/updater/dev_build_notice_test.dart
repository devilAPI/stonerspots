import 'package:app/core/settings.dart';
import 'package:app/features/updater/dev_build_notice.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);

  Future<(SettingsStore, List<Uri>)> pump(
    WidgetTester t, {
    bool dev = true,
    SettingsStore? store,
    DateTime? at,
  }) async {
    final s = store ?? SettingsStore.memory();
    final opened = <Uri>[];
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          settingsStoreProvider.overrideWithValue(s),
          isDevBuildProvider.overrideWithValue(dev),
          devNoticeClockProvider.overrideWithValue(() => at ?? now),
          devNoticeLauncherProvider.overrideWithValue((u) async {
            opened.add(u);
          }),
        ],
        child: MaterialApp(
          navigatorKey: key,
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (_, child) =>
              DevBuildNoticeHost(navigatorKey: key, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await t.pumpAndSettle();
    return (s, opened);
  }

  testWidgets('a dev build warns on start; close keeps it for next time', (
    t,
  ) async {
    final (store, _) = await pump(t);
    expect(find.text('You are using a development build'), findsOneWidget);
    expect(find.byKey(const Key('devBuildClose')), findsOneWidget);
    await t.tap(find.byKey(const Key('devBuildClose')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('devBuildNotice')), findsNothing);
    expect(store.getInt('dev_notice_snoozed_until'), isNull);
  });

  testWidgets('outside the web: a button to the latest stable release', (
    t,
  ) async {
    final (_, opened) = await pump(t);
    await t.tap(find.text('Latest stable release'));
    await t.pumpAndSettle();
    expect(opened, [Uri.parse(kStableReleaseUrl)]);
    expect(find.byKey(const Key('devBuildNotice')), findsNothing);
  });

  testWidgets('"don\'t show again" hides it for 30 days', (t) async {
    final (store, _) = await pump(t);
    await t.tap(find.byKey(const Key('devBuildSnooze')));
    await t.pump();
    await t.tap(find.byKey(const Key('devBuildClose')));
    await t.pumpAndSettle();
    expect(
      store.getInt('dev_notice_snoozed_until'),
      now.add(const Duration(days: 30)).millisecondsSinceEpoch,
    );

    // a day later: not shown; 31 days later: shown again
    await t.pumpWidget(const SizedBox());
    await pump(t, store: store, at: now.add(const Duration(days: 1)));
    expect(find.byKey(const Key('devBuildNotice')), findsNothing);
    await t.pumpWidget(const SizedBox());
    await pump(t, store: store, at: now.add(const Duration(days: 31)));
    expect(find.byKey(const Key('devBuildNotice')), findsOneWidget);
  });

  testWidgets('a release or local build shows nothing', (t) async {
    await pump(t, dev: false);
    expect(find.byKey(const Key('devBuildNotice')), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
