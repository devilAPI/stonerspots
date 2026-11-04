import 'package:app/features/legal/legal_pages.dart' show kRulesPath;
import 'package:app/features/zones/zone_consent.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('the disclaimer links the community rules and comes back', (
    t,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showZoneDisclaimer(context),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: kRulesPath,
          builder: (_, _) =>
              Scaffold(appBar: AppBar(), body: const Text('RULES')),
        ),
      ],
    );
    await t.pumpWidget(
      MaterialApp.router(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    );
    await t.tap(find.text('OPEN'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);

    await t.ensureVisible(find.byKey(const Key('zoneDisclaimerRules')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('zoneDisclaimerRules')));
    await t.pumpAndSettle();
    expect(find.text('RULES'), findsOneWidget);

    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(find.text('RULES'), findsNothing);
    expect(find.byKey(const Key('zoneDisclaimer')), findsOneWidget);
  });
}
