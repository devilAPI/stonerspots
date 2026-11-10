import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/device_insets.dart';
import 'core/glass.dart';
import 'core/settings.dart';
import 'core/tag_catalog.dart';
import 'core/theme.dart';
import 'features/home_widgets/home_widget_sync.dart';
import 'features/updater/dev_build_notice.dart';
import 'features/updater/update_ui.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGlass();
  // Read before the first frame, so saved settings never flash the default.
  final settings = await SettingsStore.load();
  // Glass needs something to refract: draw under the system bars too.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
      child: const StonerspotsApp(),
    ),
  );
}

class StonerspotsApp extends ConsumerStatefulWidget {
  const StonerspotsApp({super.key});

  @override
  ConsumerState<StonerspotsApp> createState() => _StonerspotsAppState();
}

class _StonerspotsAppState extends ConsumerState<StonerspotsApp> {
  @override
  void initState() {
    super.initState();
    // Admin-defined tags; the built-in ones are used until this arrives.
    Future.microtask(() => ref.read(tagCatalogProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(homeWidgetSyncProvider);
    ref.watch(adminTwoFactorPromptsProvider);
    return SettingsScope(
      child: MaterialApp.router(
        // Inside MaterialApp, whose own region would paint the navigation bar
        // black on every frame.
        builder: (_, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: kSystemBars,
          // the web reports no safe area itself (iOS home-screen app)
          child: DeviceInsets(
            child: DevBuildNoticeHost(
              navigatorKey: ref
                  .read(routerProvider)
                  .routerDelegate
                  .navigatorKey,
              child: UpdateBannerHost(child: child!),
            ),
          ),
        ),
        onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
        routerConfig: ref.watch(routerProvider),
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        // German is the default; fall back to it for any unsupported locale.
        localeResolutionCallback: (locale, supported) {
          for (final s in supported) {
            if (s.languageCode == locale?.languageCode) return s;
          }
          return const Locale('de');
        },
      ),
    );
  }
}
