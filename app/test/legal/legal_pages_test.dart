import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/legal/legal_info.dart';
import 'package:app/features/legal/legal_markdown.dart';
import 'package:app/features/legal/legal_pages.dart';
import 'package:app/features/legal/privacy_text.dart';
import 'package:app/features/legal/rules_text.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_helpers.dart';

Future<FakeLegal> pumpPage(
  WidgetTester t,
  Widget page, {
  String lang = 'de',
  FakeLegal? legal,
}) async {
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = legal ?? FakeLegal();
  await t.pumpWidget(
    ProviderScope(
      overrides: [legalRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ),
  );
  await t.pumpAndSettle();
  return repo;
}

/// Any text widget (also inside rich text) containing [s].
Finder textHas(String s) => find.byWidgetPredicate(
  (w) =>
      (w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').contains(s)) ||
      (w is RichText && w.text.toPlainText().contains(s)),
);

void main() {
  group('Impressum', () {
    testWidgets('shows the operator in the § 5 DDG layout, in German', (
      t,
    ) async {
      await pumpPage(t, const ImprintScreen());
      expect(find.byKey(const Key('imprintDetails')), findsOneWidget);
      expect(find.text('Angaben gemäß § 5 DDG'), findsOneWidget);
      // name twice: operator and responsible person
      expect(find.text('Erika Beispiel'), findsNWidgets(2));
      expect(find.text('c/o Adressdienst'), findsNWidgets(2));
      expect(find.text('10115 Berlin'), findsNWidgets(2));
      expect(find.text('Kontakt'), findsOneWidget);
      expect(find.text('E-Mail: erika@beispiel.test'), findsOneWidget);
      expect(find.text('Telefon: +49 30 0'), findsOneWidget);
      expect(
        find.text('Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV'),
        findsOneWidget,
      );
      expect(find.text('Hobbyprojekt'), findsOneWidget);
      expect(find.byKey(const Key('legalNotConfigured')), findsNothing);
    });

    testWidgets('and in English', (t) async {
      await pumpPage(t, const ImprintScreen(), lang: 'en');
      expect(find.text('Legal notice'), findsWidgets);
      expect(find.textContaining('§ 5 DDG'), findsOneWidget);
      expect(find.text('Email: erika@beispiel.test'), findsOneWidget);
      expect(find.text('Phone: +49 30 0'), findsOneWidget);
      expect(find.textContaining('§ 18 (2) MStV'), findsOneWidget);
    });

    testWidgets('a separate responsible person, no phone', (t) async {
      await pumpPage(
        t,
        const ImprintScreen(),
        legal: FakeLegal(
          info: const LegalInfo(
            configured: true,
            operatorName: 'Verein e. V.',
            address: 'Straße 1\n12345 Ort',
            email: 'info@beispiel.test',
            responsiblePerson: 'Max Vorstand',
          ),
        ),
      );
      expect(find.text('Verein e. V.'), findsOneWidget);
      expect(find.text('Max Vorstand'), findsOneWidget);
      expect(find.textContaining('Telefon'), findsNothing);
    });

    testWidgets('not set up: a note, no made-up details', (t) async {
      await pumpPage(
        t,
        const ImprintScreen(),
        legal: FakeLegal(info: LegalInfo.none),
      );
      expect(find.byKey(const Key('legalNotConfigured')), findsOneWidget);
      expect(find.textContaining('noch nicht eingerichtet'), findsOneWidget);
      expect(find.byKey(const Key('imprintDetails')), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Erneut versuchen'), findsNothing);
    });

    testWidgets('not set up, in English', (t) async {
      await pumpPage(
        t,
        const ImprintScreen(),
        lang: 'en',
        legal: FakeLegal(info: LegalInfo.none),
      );
      expect(
        find.text(
          'The operator of this server has not set up the legal notice yet.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('server not reachable: the same note, and try again', (
      t,
    ) async {
      final repo = await pumpPage(
        t,
        const ImprintScreen(),
        legal: FakeLegal(error: ApiException(0, 'network_error', '')),
      );
      expect(find.byKey(const Key('legalNotConfigured')), findsOneWidget);
      expect(find.byKey(const Key('imprintDetails')), findsNothing);
      repo.error = null;
      await t.tap(find.text('Erneut versuchen'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('imprintDetails')), findsOneWidget);
      expect(repo.calls, 2);
    });
  });

  group('Datenschutzerklärung', () {
    testWidgets('German text with version and the controller', (t) async {
      await pumpPage(t, const PrivacyScreen());
      expect(find.text('Datenschutzerklärung'), findsWidgets);
      expect(textHas('Stand: $kPrivacyVersionDe'), findsWidgets);
      expect(find.byKey(const Key('privacyController')), findsOneWidget);
      expect(find.text('Erika Beispiel'), findsOneWidget);
      expect(
        find.text('Kontakt für Datenschutzfragen: datenschutz@beispiel.test'),
        findsOneWidget,
      );
      // the third parties are named
      for (final s in [
        'tile.openstreetmap.org',
        'api.open-meteo.com',
        'api.pwnedpasswords.com',
        'Overpass API',
        'GitHub Pages',
        'fonts.gstatic.com',
      ]) {
        expect(textHas(s), findsWidgets, reason: s);
      }
    });

    testWidgets('English text', (t) async {
      await pumpPage(t, const PrivacyScreen(), lang: 'en');
      expect(find.text('Privacy policy'), findsWidgets);
      expect(textHas('Last updated: $kPrivacyVersionEn'), findsWidgets);
      expect(textHas('Your rights'), findsWidgets);
      expect(
        find.text('Contact for privacy questions: datenschutz@beispiel.test'),
        findsOneWidget,
      );
    });

    testWidgets('not set up: the note, the text is still there', (t) async {
      await pumpPage(
        t,
        const PrivacyScreen(),
        legal: FakeLegal(info: LegalInfo.none),
      );
      expect(find.byKey(const Key('legalNotConfigured')), findsOneWidget);
      expect(find.byKey(const Key('privacyController')), findsNothing);
      expect(textHas('Deine Rechte'), findsWidgets);
    });

    testWidgets('privacy contact falls back to the operator email', (t) async {
      await pumpPage(
        t,
        const PrivacyScreen(),
        lang: 'en',
        legal: FakeLegal(
          info: const LegalInfo(
            configured: true,
            operatorName: 'A',
            address: 'B',
            email: 'a@beispiel.test',
          ),
        ),
      );
      expect(
        find.text('Contact for privacy questions: a@beispiel.test'),
        findsOneWidget,
      );
    });
  });

  group('Nutzungsregeln', () {
    testWidgets('German: 18+, KCanG zones, OSM data is no legal advice', (
      t,
    ) async {
      await pumpPage(t, const RulesScreen());
      expect(find.text('Nutzungsregeln'), findsWidgets);
      expect(find.text('Nur ab 18'), findsOneWidget);
      expect(textHas('§ 5 Konsumcannabisgesetz'), findsWidgets);
      expect(textHas('mehr als 100 Metern'), findsWidgets);
      expect(textHas('zwischen 7 und 20 Uhr'), findsWidgets);
      expect(textHas('keine Rechtsberatung'), findsWidgets);
      expect(textHas('Liechtenstein'), findsWidgets);
    });

    testWidgets('English', (t) async {
      await pumpPage(t, const RulesScreen(), lang: 'en');
      expect(find.text('Community rules'), findsWidgets);
      expect(find.text('18+ only'), findsOneWidget);
      expect(textHas('no legal advice'), findsWidgets);
    });
  });

  group('texts', () {
    test('every text has its version line and no operator details', () {
      for (final text in [
        privacyTextDe,
        privacyTextEn,
        rulesTextDe,
        rulesTextEn,
      ]) {
        expect(text, contains('November 2026'));
        // personal details only ever come from the server
        expect(text, isNot(contains('@')));
      }
      expect(privacyTextDe, contains('{{controller}}'));
      expect(privacyTextEn, contains('{{controller}}'));
    });

    test('the Markdown subset', () {
      final blocks = parseLegalMarkdown('''
# Title

First line
second line.

## Part
- one
  more
- two
{{slot}}
After **bold**.
''');
      expect(blocks.length, 7);
      expect((blocks[0] as LegalHeading).level, 1);
      expect((blocks[1] as LegalParagraph).text, 'First line second line.');
      expect((blocks[2] as LegalHeading).text, 'Part');
      expect((blocks[3] as LegalBullet).text, 'one more');
      expect((blocks[4] as LegalBullet).text, 'two');
      expect((blocks[5] as LegalSlot).name, 'slot');
      expect((blocks[6] as LegalParagraph).text, 'After **bold**.');
      final span = legalSpan('After **bold**.', null);
      expect(span.toPlainText(), 'After bold.');
      expect(
        (span.children![1] as TextSpan).style?.fontWeight,
        FontWeight.bold,
      );
    });
  });

  group('LegalInfo', () {
    test('parses the server answer', () {
      final i = LegalInfo.fromJson({
        'configured': true,
        'operator_name': 'A',
        'address': 'B\nC',
        'email': 'a@beispiel.test',
        'responsible_person': '',
        'privacy_contact_email': '',
      });
      expect(i.configured, isTrue);
      expect(i.responsible, 'A');
      expect(i.privacyEmail, 'a@beispiel.test');
    });

    test('configured without the essentials counts as not set up', () {
      expect(
        LegalInfo.fromJson({'configured': true, 'operator_name': 'A'})
            .configured,
        isFalse,
      );
      expect(
        LegalInfo.fromJson({
          'configured': false,
          'operator_name': 'A',
          'address': 'B',
          'email': 'c',
        }).configured,
        isFalse,
      );
    });

    test('ApiLegalRepository asks GET /legal', () async {
      final a = JsonAdapter(
        (_) => (
          200,
          {
            'configured': true,
            'operator_name': 'A',
            'address': 'B',
            'email': 'a@beispiel.test',
          },
        ),
      );
      final repo = ApiLegalRepository(
        ApiClient(
          tokenStore: TokenStore.memory(),
          baseUrl: 'http://x/api/v1',
          adapter: a,
        ),
      );
      final info = await repo.fetch();
      expect(info.operatorName, 'A');
      expect(a.seen.single.method, 'GET');
      expect(a.seen.single.uri.path, '/api/v1/legal');
    });
  });
}
