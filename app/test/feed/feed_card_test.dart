import 'dart:math' as math;

import 'package:app/core/models.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/map/map_tiles.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem itemWithoutPhoto() => FeedItem(
  id: 1,
  body: 'nice bench',
  photos: const [],
  createdAt: DateTime(2026, 10, 24),
  author: const Author(id: 1, displayName: 'A'),
  spot: const Spot(id: 5, title: 'Lake bench', lat: 48.1234, lon: 11.5678),
);

void main() {
  testWidgets(
    'a post without photos shows a zoomed-in satellite view of the spot',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FeedCard(item: itemWithoutPhoto()),
            ),
          ),
        ),
      );
      final thumb = tester.widget<SatelliteThumb>(find.byType(SatelliteThumb));
      expect(thumb.lat, 48.1234);
      expect(thumb.lon, 11.5678);
      expect(thumb.zoom, 19);
      // plain tile images, no map widget per card (keeps the feed smooth)
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('Lake bench'), findsOneWidget);
    },
  );

  test('satellite tiles cover the thumbnail with the spot in its centre', () {
    const w = 400.0, h = 300.0;
    final tiles = satelliteThumbTiles(
      lat: 48.1234,
      lon: 11.5678,
      zoom: 19,
      width: w,
      height: h,
    );
    // zoom 19 is drawn from zoom-18 imagery scaled up 2x
    expect(tiles.every((t) => t.size == 512), isTrue);
    expect(tiles.every((t) => t.url.contains('World_Imagery')), isTrue);
    expect(tiles.map((t) => t.left).reduce(math.min), lessThanOrEqualTo(0));
    expect(tiles.map((t) => t.top).reduce(math.min), lessThanOrEqualTo(0));
    expect(
      tiles.map((t) => t.left + t.size).reduce(math.max),
      greaterThanOrEqualTo(w),
    );
    expect(
      tiles.map((t) => t.top + t.size).reduce(math.max),
      greaterThanOrEqualTo(h),
    );
    final centre = tiles.singleWhere(
      (t) => t.url == satelliteTileUrl(18, 139495, 90990),
    );
    expect(centre.left, closeTo(w / 2 - 0.41489777 * 512, 1e-3));
    expect(centre.top, closeTo(h / 2 - 0.58302616 * 512, 1e-3));
  });

  testWidgets('feed card shows the spot rating next to the likes', (t) async {
    Future<void> pumpItem(Spot spot) => t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FeedCard(
              item: FeedItem(
                id: 1,
                body: 'x',
                photos: const [],
                createdAt: DateTime(2026, 10, 24),
                author: const Author(id: 1, displayName: 'A'),
                spot: spot,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpItem(itemWithoutPhoto().spot);
    expect(find.byIcon(Icons.star), findsNothing);
    await pumpItem(
      const Spot(
        id: 5,
        title: 'Lake bench',
        lat: 48.1,
        lon: 11.5,
        ratingAvg: 4.0,
        ratingCount: 3,
      ),
    );
    expect(find.text('4.0 (3)'), findsOneWidget);
  });
}
