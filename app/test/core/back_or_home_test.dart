import 'package:app/core/back_or_home.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A page outside the tab shell, built like the app's.
Widget _page(String title) => BackToHomeScope(
  child: Scaffold(
    appBar: AppBar(leading: const BackOrHomeButton(), title: Text(title)),
    body: Builder(
      builder: (c) => TextButton(
        // like the add-spot screen once the spot is created
        onPressed: () =>
            c.canPop() ? c.pushReplacement('/spot/7') : c.go('/spot/7'),
        child: const Text('save'),
      ),
    ),
  ),
);

Future<GoRouter> _pump(WidgetTester t, String initial) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home map')),
      ),
      GoRoute(path: '/spot/new', builder: (_, _) => _page('add spot')),
      GoRoute(path: '/spot/:id', builder: (_, _) => _page('spot')),
    ],
  );
  await t.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
  await t.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('a page opened alone gets a back button to the home map', (
    t,
  ) async {
    await _pump(t, '/spot/5'); // e.g. a shared link
    await t.tap(find.byKey(const Key('backToHome')));
    await t.pumpAndSettle();
    expect(find.text('home map'), findsOneWidget);
  });

  testWidgets('system back on a page opened alone goes home, not out', (
    t,
  ) async {
    await _pump(t, '/spot/5');
    final handled = await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(handled, isTrue); // the app was not closed
    expect(find.text('home map'), findsOneWidget);
  });

  testWidgets('a pushed page keeps its normal back button', (t) async {
    final router = await _pump(t, '/');
    router.push('/spot/5');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('backToHome')), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('home map'), findsOneWidget);
  });

  testWidgets('after creating a spot, back leads to the map, not the form', (
    t,
  ) async {
    final router = await _pump(t, '/');
    router.push('/spot/new');
    await t.pumpAndSettle();
    await t.tap(find.text('save'));
    await t.pumpAndSettle();
    expect(find.text('spot'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('home map'), findsOneWidget);
  });
}
