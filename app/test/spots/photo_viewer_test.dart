import 'package:app/features/spots/photo_viewer.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> open(WidgetTester t, {int index = 0}) async {
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showPhotoViewer(c, ['a', 'b', 'c'], index),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('opens at the tapped index with a page indicator', (t) async {
    await open(t, index: 1);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
  });

  testWidgets('swiping changes the page', (t) async {
    await open(t);
    expect(find.text('1 / 3'), findsOneWidget);
    await t.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await t.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
  });

  testWidgets('arrow keys page and Escape closes', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('close button closes', (t) async {
    await open(t);
    await t.tap(find.byKey(const Key('photoViewerClose')));
    await t.pumpAndSettle();
    expect(find.byType(PageView), findsNothing);
  });
}
