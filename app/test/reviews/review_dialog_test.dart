import 'package:app/core/api_client.dart';
import 'package:app/features/reviews/review_dialog.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_helpers.dart';

Future<void> open(
  WidgetTester t,
  Future<void> Function(int, String) onSave, {
  bool existing = false,
}) async {
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showReviewDialog(
            c,
            existing: existing ? review(1, rating: 2, body: 'meh') : null,
            onSave: onSave,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

FilledButton saveButton(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('reviewSave')));

void main() {
  testWidgets('save is disabled until a star is chosen', (t) async {
    await open(t, (_, _) async {});
    expect(saveButton(t).onPressed, isNull);
    await t.tap(find.byKey(const Key('reviewStar_4')));
    await t.pump();
    expect(saveButton(t).onPressed, isNotNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('reviewStar_4')),
        matching: find.byIcon(Icons.star),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('reviewStar_5')),
        matching: find.byIcon(Icons.star_border),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stars are focusable buttons (keyboard accessible)', (t) async {
    await open(t, (_, _) async {});
    final star = find.byKey(const Key('reviewStar_3'));
    expect(t.widget(star), isA<IconButton>());
  });

  testWidgets('saves rating and trimmed text and closes', (t) async {
    int? r;
    String? b;
    await open(t, (rating, body) async {
      r = rating;
      b = body;
    });
    await t.tap(find.byKey(const Key('reviewStar_5')));
    await t.enterText(find.byKey(const Key('reviewBody')), '  great  ');
    await t.pump();
    await t.tap(find.byKey(const Key('reviewSave')));
    await t.pumpAndSettle();
    expect(r, 5);
    expect(b, 'great');
    expect(find.byKey(const Key('reviewSave')), findsNothing);
  });

  testWidgets('prefills when editing and shows a counter', (t) async {
    await open(t, (_, _) async {}, existing: true);
    expect(find.text('meh'), findsOneWidget);
    expect(find.text('3/1000'), findsOneWidget);
    expect(saveButton(t).onPressed, isNotNull);
  });

  for (final c in {
    'invalid_rating': 'Please choose 1 to 5 stars',
    'invalid_body': 'The text is too long',
    'own_spot': 'You cannot review your own spot',
    'weird': 'Something went wrong',
  }.entries) {
    testWidgets('shows inline error for ${c.key} and stays open', (t) async {
      await open(t, (_, _) async => throw ApiException(400, c.key, 'x'));
      await t.tap(find.byKey(const Key('reviewStar_2')));
      await t.pump();
      await t.tap(find.byKey(const Key('reviewSave')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('reviewError')),
          matching: find.text(c.value),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('reviewSave')), findsOneWidget);
    });
  }

  testWidgets('a non-API error shows the generic message', (t) async {
    await open(t, (_, _) async => throw StateError('boom'));
    await t.tap(find.byKey(const Key('reviewStar_2')));
    await t.pump();
    await t.tap(find.byKey(const Key('reviewSave')));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
  });
}
