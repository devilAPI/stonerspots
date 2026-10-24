import 'package:app/core/models.dart';
import 'package:app/features/map/map_filter_bar.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> pumpBar(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final c = ProviderContainer();
  addTearDown(c.dispose);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: MapFilterBar()),
      ),
    ),
  );
  return c;
}

Future<void> reveal(WidgetTester t, String key) async {
  await t.scrollUntilVisible(
    find.byKey(Key(key)),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pump();
}

void main() {
  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('tag chips toggle the controller state at $size', (t) async {
      final c = await pumpBar(t, size);
      // categories first, then the divider, then the seven tags
      expect(find.text('All'), findsOneWidget);
      await reveal(t, 'mapTagDivider');
      final roof = t.getTopLeft(find.byKey(const Key('mapTag-roof')));
      final divider = t.getTopLeft(find.byKey(const Key('mapTagDivider')));
      expect(divider.dx, lessThan(roof.dx));
      expect(find.byKey(const Key('mapTagsClear')), findsNothing);

      await t.tap(find.byKey(const Key('mapTag-roof')));
      await t.pump();
      expect(c.read(spotsControllerProvider).tags, [SpotTag.roof]);
      expect(
        t.widget<FilterChip>(find.byKey(const Key('mapTag-roof'))).selected,
        isTrue,
      );

      await reveal(t, 'mapTag-lit');
      await t.tap(find.byKey(const Key('mapTag-lit')));
      await t.pump();
      expect(c.read(spotsControllerProvider).tags, [SpotTag.roof, SpotTag.lit]);

      await reveal(t, 'mapTagsClear');
      await t.tap(find.byKey(const Key('mapTagsClear')));
      await t.pump();
      expect(c.read(spotsControllerProvider).tags, isEmpty);
      expect(find.byKey(const Key('mapTagsClear')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('category chips still set the category', (t) async {
    final c = await pumpBar(t, const Size(400, 800));
    await t.tap(find.text('Bench'));
    await t.pump();
    expect(c.read(spotsControllerProvider).category, 'bench');
  });
}
