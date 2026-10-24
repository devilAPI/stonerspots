// ignore_for_file: avoid_print
// Drives the real app (real window, real plugins, real network) through the
// add-spot flow and reports where it gets stuck.
//   flutter test integration_test/add_spot_flow_test.dart -d linux \
//     --dart-define-from-file=env/local.json   (API must be running)
import 'package:app/core/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/spots/location_picker.dart';
import 'package:app/main.dart';
import 'package:app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<bool> waitFor(WidgetTester t, Finder f, Duration max) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < max) {
    await t.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) {
      print('  found $f after ${sw.elapsedMilliseconds} ms');
      return true;
    }
  }
  print('  NOT found $f after ${max.inSeconds} s');
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add spot flow', (t) async {
    final store = TokenStore.memory();
    final session = await ApiAuthRepository(ApiClient(tokenStore: store))
        .login('demo@example.com', 'correct-horse-1');
    await store.write(session.tokens);

    await t.pumpWidget(
      ProviderScope(
        overrides: [tokenStoreProvider.overrideWithValue(store)],
        child: const StonerspotsApp(),
      ),
    );
    await t.pump(const Duration(seconds: 2));
    final container = ProviderScope.containerOf(
      t.element(find.byType(StonerspotsApp)),
    );
    container.read(routerProvider).go('/spot/new');
    await t.pump(const Duration(milliseconds: 500));
    print('STEP 1 open /spot/new');

    final mapShown = await waitFor(
      t,
      find.byType(LocationPicker),
      const Duration(seconds: 40),
    );
    if (!mapShown) {
      print('RESULT: the map never appears -> cannot place a point');
      return;
    }
    print(
      'STEP 2 map visible; progress spinner still there: ${find.byType(CircularProgressIndicator).evaluate().isNotEmpty}',
    );

    await t.tapAt(t.getCenter(find.byType(LocationPicker)));
    await t.pump(const Duration(milliseconds: 600));
    print(
      'STEP 3 tapped map; pin visible: ${find.byIcon(Icons.location_on).evaluate().isNotEmpty}',
    );

    await t.enterText(find.byKey(const Key('title')), 'Integrationstest');
    await t.pump(const Duration(milliseconds: 300));

    final save = find.byKey(const Key('save'));
    await t.ensureVisible(save);
    final btn = t.widget<FilledButton>(save);
    print('STEP 5 save button enabled: ${btn.onPressed != null}');
    if (btn.onPressed == null) {
      print('RESULT: Save stays disabled (needs title + a point)');
      return;
    }
    await t.tap(save);
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    final loc = container
        .read(routerProvider)
        .routeInformationProvider
        .value
        .uri
        .toString();
    print(
      'STEP 6 after save: location=$loc, duplicate banner=${find.byKey(const Key("addAnyway")).evaluate().isNotEmpty}',
    );
    final texts = t
        .widgetList<Text>(find.byType(Text))
        .map((e) => e.data)
        .whereType<String>()
        .where(
          (s) =>
              s.toLowerCase().contains('wrong') ||
              s.contains('schief') ||
              s.contains('Fehler') ||
              s.contains('error'),
        )
        .toList();
    print('       error texts on screen: $texts');
  });
}
