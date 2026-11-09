import 'package:app/core/theme.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, double width) => t.pumpWidget(
  MaterialApp(
    home: Center(
      child: SizedBox(
        width: width,
        child: const SatelliteThumb(lat: 48.1, lon: 11.5),
      ),
    ),
  ),
);

/// The accent-coloured dot on the spot.
Finder get _dot => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).color == kAccent,
);

void main() {
  testWidgets('a large thumbnail marks the spot with a dot', (t) async {
    await _pump(t, 400);
    expect(_dot, findsOneWidget);
  });

  testWidgets('a small list-row thumbnail has no dot', (t) async {
    await _pump(t, 56);
    expect(_dot, findsNothing);
  });

  testWidgets('a large thumbnail carries the Esri credit', (t) async {
    await _pump(t, 400);
    expect(find.text('Esri World Imagery'), findsOneWidget);
  });

  testWidgets('a small list-row thumbnail has no credit in it', (t) async {
    await _pump(t, 56);
    expect(find.textContaining('Imagery'), findsNothing);
  });
}
