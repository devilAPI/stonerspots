import 'package:app/core/settings.dart';
import 'package:app/features/zones/zone_consent.dart';
import 'package:app/core/models.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/map/spot_preview_sheet.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../saved/saved_helpers.dart' show FakeAuth, FakeSaved;

Future<void> pumpSheet(
  WidgetTester t,
  Spot spot, {
  Size? size,
  FakeSaved? saved,
  void Function(int userId)? onOpenAuthor,
}) async {
  if (size != null) {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        // zones (and their first-use disclaimer) are tested in test/zones
        zonesEnabledProvider.overrideWith(() => BoolSetting('zones_enabled')),
        savedRepositoryProvider.overrideWithValue(saved ?? FakeSaved()),
        authControllerProvider.overrideWith(() => FakeAuth(null)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SpotPreviewSheet(
            spot: spot,
            onOpen: () {},
            onOpenAuthor: onOpenAuthor,
          ),
        ),
      ),
    ),
  );
}

const noPhoto = Spot(
  id: 1,
  title: 'Lake bench',
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

  testWidgets('user photos come first, then the top-down view', (t) async {
    await pumpSheet(
      t,
      const Spot(
        id: 1,
        title: 'Lake bench',
        lat: 48.1,
        lon: 11.6,
        coverUrl: 'http://test/api/v1/media/a.jpg',
      ),
    );
    // the photo comes first, the top-down view follows it
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(SatelliteThumb), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const Key('galleryPhoto_0'))).dx,
      lessThan(t.getTopLeft(find.byType(SatelliteThumb)).dx),
    );
  });

  testWidgets(
    'an empty cover url (what the API sends without photos) does not crash',
    (t) async {
      await pumpSheet(
        t,
        const Spot(
          id: 1,
          title: 'Lake bench',
          lat: 48.1,
          lon: 11.6,
          coverUrl: '',
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byType(SatelliteThumb), findsOneWidget);
    },
  );

  testWidgets('fits a short landscape phone without overflow', (t) async {
    await pumpSheet(t, noPhoto, size: const Size(844, 390));
    expect(t.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('shows the rating only when there are reviews', (t) async {
    await pumpSheet(t, noPhoto);
    expect(find.byIcon(Icons.star), findsNothing);
    await pumpSheet(
      t,
      const Spot(
        id: 1,
        title: 'Lake bench',
        lat: 48.1,
        lon: 11.6,
        ratingAvg: 4.25,
        ratingCount: 8,
      ),
    );
    expect(find.text('4.3 (8)'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tags show as small chips', (t) async {
    await pumpSheet(
      t,
      const Spot(
        id: 1,
        title: 'T',
        lat: 1,
        lon: 2,
        tags: [SpotTag.roof, SpotTag.water],
      ),
    );
    expect(find.byKey(const Key('previewTag-roof')), findsOneWidget);
    expect(find.byKey(const Key('previewTag-water')), findsOneWidget);
    expect(find.byKey(const Key('previewTag-lit')), findsNothing);
    expect(find.text('Roof'), findsOneWidget);
  });

  testWidgets('has a bookmark, separate from the likes', (t) async {
    await pumpSheet(t, noPhoto);
    expect(find.byKey(const Key('saveSpot')), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('a long title leaves room for the bookmark', (t) async {
    await pumpSheet(
      t,
      Spot(id: 1, title: 'Very long name ' * 8, lat: 1, lon: 2),
      size: const Size(320, 640),
    );
    expect(t.takeException(), isNull);
    expect(find.byKey(const Key('saveSpot')).hitTestable(), findsOneWidget);
  });

  testWidgets('no tags: no chip row', (t) async {
    await pumpSheet(t, noPhoto);
    expect(find.byType(Chip), findsNothing);
  });

  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('all tags fit at $size', (t) async {
      await pumpSheet(
        t,
        Spot(id: 1, title: 'T', lat: 1, lon: 2, tags: SpotTag.values),
        size: size,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('shows who added the spot; tapping opens them', (t) async {
    final opened = <int>[];
    await pumpSheet(
      t,
      const Spot(
        id: 1,
        title: 'Lake bench',
        lat: 48.1,
        lon: 11.6,
        author: Author(id: 4, displayName: 'Ann'),
      ),
      onOpenAuthor: opened.add,
    );
    expect(find.text('Added by'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
    expect(find.byKey(const Key('authorAvatar-4')), findsOneWidget);
    await t.tap(find.byKey(const Key('authorLink-4')));
    expect(opened, [4]);
  });

  testWidgets('an owner who is gone shows as a deleted account', (t) async {
    await pumpSheet(t, noPhoto);
    expect(find.byKey(const Key('spotOwnerDeleted')), findsOneWidget);
    expect(find.text('Deleted account'), findsOneWidget);
    expect(
      find.byType(InkWell).evaluate().where((e) {
        final k = e.widget.key;
        return k is ValueKey<String> && k.value.startsWith('authorLink-');
      }),
      isEmpty,
    );
  });
}
