import 'package:app/core/api_client.dart';
import 'package:app/features/spots/add_spot_errors.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppLocalizations> l10n(WidgetTester t, String lang) async {
  late AppLocalizations l;
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (c) {
          l = AppLocalizations.of(c);
          return const SizedBox();
        },
      ),
    ),
  );
  return l;
}

ApiException e(int status, String code, [String msg = 'server said no']) =>
    ApiException(status, code, msg);

void main() {
  testWidgets(
    'an unsupported photo format says so instead of "something went wrong"',
    (t) async {
      final l = await l10n(t, 'en');
      final text = addSpotErrorText(l, e(415, 'unsupported_type'));
      expect(text.toLowerCase(), contains('format'));
      expect(text, isNot(l.errorGeneric));
      expect(text, contains('AVIF'));
    },
  );

  testWidgets(
    'too large photos, bad locations and network problems have their own text',
    (t) async {
      final l = await l10n(t, 'en');
      expect(addSpotErrorText(l, e(413, 'too_large')), contains('8'));
      expect(
        addSpotErrorText(l, e(400, 'invalid_location')),
        l.placeSearchOutside,
      );
      expect(addSpotErrorText(l, e(0, 'network_error')), l.errorNetwork);
    },
  );

  testWidgets(
    'unknown server errors still show the server message, not just a generic line',
    (t) async {
      final l = await l10n(t, 'en');
      final text = addSpotErrorText(
        l,
        e(500, 'internal', 'database is on fire'),
      );
      expect(text, contains(l.errorGeneric));
      expect(text, contains('database is on fire'));
    },
  );

  testWidgets('non-API errors fall back to the generic text, in German too', (
    t,
  ) async {
    final l = await l10n(t, 'de');
    expect(addSpotErrorText(l, StateError('x')), l.errorGeneric);
    expect(
      addSpotErrorText(l, e(415, 'unsupported_type')),
      contains('Bildformat'),
    );
  });
}
