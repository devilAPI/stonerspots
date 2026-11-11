import 'package:app/core/models.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/feed/feed_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements FeedRepository {
  final tagCalls = <List<SpotTag>>[];

  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
    List<SpotTag> tags = const [],
    bool following = false,
    int? radiusKm,
  }) async {
    tagCalls.add(tags);
    return const FeedPage([], null);
  }
}

Future<void> openFilters(WidgetTester t) async {
  await t.tap(find.byKey(const Key('feedFilters')));
  await t.pumpAndSettle();
}

Future<void> tapInSheet(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('feed tags filter from the sheet and clear at $size', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = _Repo();
      await t.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FeedScreen(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(repo.tagCalls.last, isEmpty);
      // the sort is three tabs; no filter row while nothing is on
      for (final s in ['newest', 'top', 'nearby']) {
        expect(find.byKey(Key('feedSort-$s')), findsOneWidget);
      }
      expect(find.byKey(const Key('feedActiveFilters')), findsNothing);

      await openFilters(t);
      await tapInSheet(t, 'feedTag-roof');
      expect(repo.tagCalls.last, [SpotTag.roof]);
      expect(
        t.widget<FilterChip>(find.byKey(const Key('feedTag-roof'))).selected,
        isTrue,
      );
      await tapInSheet(t, 'feedTag-quiet');
      expect(repo.tagCalls.last, [SpotTag.roof, SpotTag.quiet]);
      await tapInSheet(t, 'feedFiltersDone');
      expect(find.byType(FeedFilterSheet), findsNothing);

      // what is on shows under the sort, each removable
      expect(find.byKey(const Key('feedActiveFilters')), findsOneWidget);
      final badge = t.widget<Badge>(
        find.descendant(
          of: find.byKey(const Key('feedFilters')),
          matching: find.byType(Badge),
        ),
      );
      expect(badge.isLabelVisible, isTrue);
      final roof = find.byKey(const Key('feedActive-roof'));
      await t.tap(
        find.descendant(of: roof, matching: find.byIcon(Icons.clear)),
      );
      await t.pumpAndSettle();
      expect(repo.tagCalls.last, [SpotTag.quiet]);

      await openFilters(t);
      await tapInSheet(t, 'feedFiltersReset');
      expect(repo.tagCalls.last, isEmpty);
      await tapInSheet(t, 'feedFiltersDone');
      expect(find.byKey(const Key('feedActiveFilters')), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
