import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/glass.dart';
import 'core/tag_catalog.dart';
import 'core/theme.dart';
import 'features/home_widgets/home_widget_sync.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initGlass();
  // Glass needs something to refract: draw under the system bars too.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const ProviderScope(child: StonerspotsApp()));
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
    return MaterialApp.router(
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
    );
  }
}
