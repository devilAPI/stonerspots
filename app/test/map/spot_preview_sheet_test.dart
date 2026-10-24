import 'package:app/core/models.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/map/spot_preview_sheet.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpSheet(WidgetTester t, Spot spot, {Size? size}) async {
  if (size != null) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SpotPreviewSheet(spot: spot, onOpen: () {}),
      ),
    ),
  );
}

const noPhoto = Spot(
  id: 1,
  title: 'Lake bench',
  category: 'bench',
  lat: 48.1,
  lon: 11.6,
  likeCount: 2,
);

void main() {
  testWidgets('a spot without user photos shows the top-down view', (t) async {
    await pumpSheet(t, noPhoto);
    final thumb = t.widget<SatelliteThumb>(find.byType(SatelliteThumb));
    expect(thumb.lat, 48.1);
    expect(thumb.lon, 11.6);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text('Lake bench'), findsOneWidget);
  });

  testWidgets('a user photo is preferred over the top-down view', (t) async {
    await pumpSheet(
      t,
      const Spot(
        id: 1,
        title: 'Lake bench',
        category: 'bench',
        lat: 48.1,
        lon: 11.6,
        coverUrl: 'http://test/api/v1/media/a.jpg',
      ),
    );
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(SatelliteThumb), findsNothing);
  });

  testWidgets('fits a short landscape phone without overflow', (t) async {
    await pumpSheet(t, noPhoto, size: const Size(844, 390));
    expect(t.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget);
  });
}
