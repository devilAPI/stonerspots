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
    FeedItem(
      id: 1,
      body: 'nice bench',
      photos: const [],
      createdAt: DateTime(2026, 10, 24),
      author: const Author(id: 1, displayName: 'A'),
      spot: const Spot(id: 5, title: 'Lake bench', lat: 48.1, lon: 11.5),
    ),
  ], null);
}

void main() {
  testWidgets('next to a nav rail the cards keep their readable width', (
    t,
  ) async {
    t.view.physicalSize = const Size(1240, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    const rail = 260.0;
    await t.pumpWidget(
      ProviderScope(
        overrides: [feedRepositoryProvider.overrideWithValue(_Repo())],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Row(
            children: [
              SizedBox(width: rail),
              Expanded(child: FeedScreen()),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final card = find.byType(FeedCard);
    expect(t.getSize(card).width, kContentMaxWidth);
    // centred in the feed pane, not in the whole window
    final paneCentre = rail + (1240 - rail) / 2;
    expect(t.getCenter(card).dx, closeTo(paneCentre, 0.5));
  });
}
