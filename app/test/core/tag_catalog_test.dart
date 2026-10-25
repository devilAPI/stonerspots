import 'package:app/core/models.dart';
import 'package:app/core/spot_tag_widgets.dart';
import 'package:app/core/tag_catalog.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements TagRepository {
  _Repo(this.result);
  final Object result; // List<SpotTag> or an error to throw

  @override
  Future<List<SpotTag>> list() async {
    if (result is List<SpotTag>) return result as List<SpotTag>;
    throw result;
  }
}

Future<ProviderContainer> pump(WidgetTester t, TagRepository repo) async {
  addTearDown(SpotTag.resetCatalog);
  await t.pumpWidget(
    ProviderScope(
      overrides: [tagRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              SpotTagSelector(selected: const [], onChanged: (_) {}),
              const SpotTagChips(tags: [SpotTag('fire')]),
            ],
          ),
        ),
      ),
    ),
  );
  return ProviderScope.containerOf(t.element(find.byType(SpotTagSelector)));
}

void main() {
  testWidgets('loading the catalog shows admin-made tags with their names', (
    t,
  ) async {
    final c = await pump(
      t,
      _Repo(const [
        SpotTag(
          'fire',
          nameDe: 'Feuerstelle',
          nameEn: 'Fire pit',
          icon: 'fire',
        ),
        SpotTag.roof,
      ]),
    );
    // built-ins until loaded; the chip of an unknown tag shows its key
    expect(find.byKey(const Key('tag-quiet')), findsOneWidget);
    expect(find.text('fire'), findsOneWidget);

    await c.read(tagCatalogProvider.notifier).load();
    await t.pump();
    expect(find.byKey(const Key('tag-fire')), findsOneWidget);
    expect(find.byKey(const Key('tag-quiet')), findsNothing);
    expect(find.text('Feuerstelle'), findsNWidgets(2)); // selector + chip
    expect(find.byIcon(Icons.local_fire_department), findsNWidgets(2));
  });

  testWidgets('a failed load keeps the current catalog', (t) async {
    final c = await pump(t, _Repo(Exception('offline')));
    await c.read(tagCatalogProvider.notifier).load();
    await t.pump();
    expect(find.byKey(const Key('tag-quiet')), findsOneWidget);
    expect(c.read(tagCatalogProvider), SpotTag.builtIn);
  });

  test('unknown icon names fall back to a generic tag icon', () {
    expect(
      spotTagIcon(const SpotTag('x', icon: 'no_such_icon')),
      kFallbackTagIcon,
    );
    expect(spotTagIcon(SpotTag.water), Icons.water_drop);
  });
}
