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
  spot: const Spot(
    id: 5,
    title: 'Lake bench',
    category: 'bench',
    lat: 48.1234,
    lon: 11.5678,
  ),
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
      expect(find.byType(SatelliteThumb), findsOneWidget);
      final camera = MapCamera.of(tester.element(find.byType(TileLayer)));
      expect(camera.center.latitude, closeTo(48.1234, 1e-6));
      expect(camera.center.longitude, closeTo(11.5678, 1e-6));
      expect(camera.zoom, 19);
      expect(find.text('Lake bench'), findsOneWidget);
    },
  );

  testWidgets(
    'the satellite layer uses an imagery source, not the street map',
    (tester) async {
      late TileLayer layer;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              layer = buildSatelliteTileLayer();
              return const SizedBox();
            },
          ),
        ),
      );
      expect(layer.urlTemplate, contains('World_Imagery'));
      expect(layer.maxNativeZoom, 18);
    },
  );

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
        category: 'bench',
        lat: 48.1,
        lon: 11.5,
        ratingAvg: 4.0,
        ratingCount: 3,
      ),
    );
    expect(find.text('4.0 (3)'), findsOneWidget);
  });
}
