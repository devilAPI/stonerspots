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
  }) async {
    tagCalls.add(tags);
    return const FeedPage([], null);
  }
}

Future<void> reveal(WidgetTester t, String key) async {
  // the tag row is the horizontal scrollable around the first tag chip
  final row = find.descendant(
    of: find.byKey(const Key('feedTagRow')),
    matching: find.byType(Scrollable),
  );
  await t.scrollUntilVisible(find.byKey(Key(key)), 100, scrollable: row);
  await t.ensureVisible(find.byKey(Key(key)));
  await t.pump();
}

void main() {
  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('feed tag chips filter and clear at $size', (t) async {
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
      expect(find.text('All'), findsNothing); // no category chips
      expect(find.byType(ChoiceChip), findsNWidgets(3)); // sort chips only

      await t.tap(find.byKey(const Key('feedTag-roof')));
      await t.pumpAndSettle();
      expect(repo.tagCalls.last, [SpotTag.roof]);
      expect(
        t.widget<FilterChip>(find.byKey(const Key('feedTag-roof'))).selected,
        isTrue,
      );

      await reveal(t, 'feedTag-quiet');
      await t.tap(find.byKey(const Key('feedTag-quiet')));
      await t.pumpAndSettle();
      expect(repo.tagCalls.last, [SpotTag.roof, SpotTag.quiet]);

      await reveal(t, 'feedTagsClear');
      final clear = find.byKey(const Key('feedTagsClear'));
      await t.tap(clear);
      await t.pumpAndSettle();
      expect(repo.tagCalls.last, isEmpty);
      expect(t.takeException(), isNull);
    });
  }
}
