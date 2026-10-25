import 'package:app/core/models.dart';
import 'package:app/core/responsive.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/feed/feed_screen.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements FeedRepository {
  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
    List<SpotTag> tags = const [],
  }) async => FeedPage([
    for (var i = 1; i <= 6; i++)
      FeedItem(
        id: i,
        // different text lengths, so cards differ in natural height
        body: i.isEven ? 'nice bench' : 'a long text about this spot ' * 6,
        photos: const [],
        createdAt: DateTime(2026, 10, 24),
        author: const Author(id: 1, displayName: 'A'),
        spot: Spot(id: i, title: 'Spot $i', lat: 48.1, lon: 11.5),
      ),
  ], null);
}

/// Pumps the feed in a [window], with a [rail] wide strip left of it like the
/// app's navigation rail.
Future<void> pumpFeed(WidgetTester t, Size window, {double rail = 0}) async {
  t.view.physicalSize = window;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [feedRepositoryProvider.overrideWithValue(_Repo())],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Row(
          children: [
            SizedBox(width: rail),
            const Expanded(child: FeedScreen()),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

FeedCard cardWidget(WidgetTester t, int index) =>
    t.widget<FeedCard>(find.byType(FeedCard).at(index));

Rect cardRect(WidgetTester t, int index) =>
    t.getRect(find.byType(FeedCard).at(index));

void main() {
  test('feed columns grow with the pane width', () {
    expect(feedColumns(500), 1);
    expect(feedColumns(700), 2);
    expect(feedColumns(1000), 3);
    expect(feedColumns(1400), 4);
    expect(feedColumns(3000), kFeedMaxColumns);
  });

  testWidgets('phone portrait: one full-width card per row', (t) async {
    await pumpFeed(t, const Size(400, 800));
    expect(cardWidget(t, 0).layout, FeedCardLayout.stacked);
    expect(cardRect(t, 0).width, 400);
    expect(cardRect(t, 1).top, greaterThanOrEqualTo(cardRect(t, 0).bottom));
  });

  testWidgets('phone landscape: picture beside the text, not a grid', (
    t,
  ) async {
    await pumpFeed(t, const Size(844, 390), rail: 80);
    expect(cardWidget(t, 0).layout, FeedCardLayout.side);
    // the card fits the short screen instead of a 4:3 picture of full width
    expect(cardRect(t, 0).height, lessThan(240));
  });

  testWidgets('tablet portrait: two columns', (t) async {
    await pumpFeed(t, const Size(800, 1200), rail: 80);
    expect(cardWidget(t, 0).layout, FeedCardLayout.tile);
    expect(cardRect(t, 1).top, cardRect(t, 0).top);
    expect(cardRect(t, 2).top, greaterThanOrEqualTo(cardRect(t, 0).bottom));
  });

  testWidgets('desktop next to the nav rail: three columns, equal heights', (
    t,
  ) async {
    const rail = 260.0;
    await pumpFeed(t, const Size(1240, 900), rail: rail);
    final row = [for (var i = 0; i < 3; i++) cardRect(t, i)];
    expect(row.map((r) => r.top).toSet(), hasLength(1));
    // short and long posts share the row height, so the cards line up
    expect(row.map((r) => r.height).toSet(), hasLength(1));
    expect(cardRect(t, 3).top, greaterThanOrEqualTo(row[0].bottom));
    // centred in the feed pane, not in the whole window
    final mid = (row.first.left + row.last.right) / 2;
    expect(mid, closeTo(rail + (1240 - rail) / 2, 0.5));
  });

  testWidgets('very wide window: four columns, kept to a maximum width', (
    t,
  ) async {
    await pumpFeed(t, const Size(2560, 1200), rail: 260);
    final row = [for (var i = 0; i < 4; i++) cardRect(t, i)];
    expect(row.map((r) => r.top).toSet(), hasLength(1));
    expect(row.last.right - row.first.left, lessThanOrEqualTo(1400));
  });
}
