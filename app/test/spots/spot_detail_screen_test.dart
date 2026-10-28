import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/responsive.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/spots/maps_link.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/spot_detail_screen.dart';
import 'package:app/features/spots/spot_link.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/reviews/reviews_repository.dart';
import 'package:app/features/spots/photo_viewer.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../reviews/review_helpers.dart';
import 'update_helpers.dart';

class _Api implements SpotApi {
  _Api({
    this.cover,
    this.tags = const [],
    this.authorId = 9,
    this.locked = false,
  });
  final String? cover;
  bool locked;
  int likes = 0;
  List<SpotTag> tags;
  final int authorId;
  final savedTags = <List<SpotTag>>[];
  Object? setTagsError;

  @override
  Future<Spot> getSpot(int id) async => Spot(
    id: 5,
    title: 'Lake bench',
    lat: 1,
    lon: 2,
    likeCount: 3,
    coverUrl: cover,
    ratingAvg: 4.5,
    ratingCount: 2,
    tags: tags,
    author: Author(id: authorId, displayName: 'Ann'),
    locked: locked,
  );
  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) async {
    likes++;
    return const LikeResult(liked: true, likeCount: 4);
  }

  @override
  Future<Spot> setTags(int id, List<SpotTag> tags) async {
    savedTags.add(tags);
    if (setTagsError != null) throw setTagsError!;
    this.tags = tags;
    return await getSpot(id);
  }

  @override
  Future<Spot> createSpot(SpotDraft d, {bool force = false}) =>
      throw UnimplementedError();
  @override
  Future<void> report(String t, int id, String r) async {}
}

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

/// Records the admin calls the spot page makes.
class _Admin implements AdminRepository {
  _Admin(this.api);
  final _Api api;
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AdminSpot> updateSpot(int id, AdminSpotPatch patch) async {
    calls.add('spot:$id:${patch.toJson()}');
    if (patch.locked != null) api.locked = patch.locked!;
    return AdminSpot.fromSpot(await api.getSpot(id));
  }

  @override
  Future<void> updateUpdate(int id, AdminUpdatePatch patch) async =>
      calls.add('update:$id:${patch.toJson()}');

  @override
  Future<void> deleteUpdate(int id) async => calls.add('delete:$id');
}

late FakeUpdates updates;
late FakeReviews reviews;

Future<_Api> _pump(
  WidgetTester tester,
  User? user, {
  UrlLauncher? launcher,
  List<FeedItem>? items,
  String? cover,
  List<SpotTag> tags = const [],
  int authorId = 9,
  _Api? withApi,
  bool locked = false,
  AdminRepository? admin,
  LinkSharer? sharer,
}) async {
  final api =
      withApi ??
      _Api(cover: cover, tags: tags, authorId: authorId, locked: locked);
  updates = FakeUpdates(items: items);
  reviews = FakeReviews([
    ReviewsPage(
      summary: summaryOf({4: 1, 5: 1}),
      items: [
        review(1, rating: 4),
        review(2, rating: 5, name: 'Cy'),
      ],
    ),
  ]);
  final router = GoRouter(
    initialLocation: '/spot/5',
    routes: [
      GoRoute(
        path: '/spot/:id',
        builder: (_, _) => const SpotDetailScreen(spotId: 5),
      ),
      GoRoute(
        path: '/login',
        builder: (_, s) =>
            Scaffold(body: Text('login from ${s.uri.queryParameters['from']}')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spotApiProvider.overrideWithValue(api),
        spotUpdatesRepositoryProvider.overrideWithValue(updates),
        reviewsRepositoryProvider.overrideWithValue(reviews),
        authControllerProvider.overrideWith(() => _Auth(user)),
        if (launcher != null) urlLauncherProvider.overrideWithValue(launcher),
        if (admin != null) adminRepositoryProvider.overrideWithValue(admin),
        if (sharer != null) linkSharerProvider.overrideWithValue(sharer),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void _portrait(WidgetTester t) {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// The page is a lazy list: scroll the main (first vertical) scrollable
/// until [f] is built, then fully into view. Scrolls in code rather than by
/// dragging, since a drag over the location map moves the map instead.
Future<void> _scrollTo(WidgetTester t, Finder f) async {
  final list = t.state<ScrollableState>(
    find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first,
  );
  while (f.evaluate().isEmpty) {
    final p = list.position;
    if (p.pixels >= p.maxScrollExtent) break;
    p.jumpTo((p.pixels + 300).clamp(0, p.maxScrollExtent));
    await t.pump();
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('logged-out like pushes login, which pops back to the spot', (
    tester,
  ) async {
    final api = await _pump(tester, null);
    expect(find.text('3 likes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('like')));
    await tester.pumpAndSettle();
    // pushed, not a redirect: no from, back leads to the spot
    expect(find.text('login from null'), findsOneWidget);
    expect(api.likes, 0);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
    expect(find.text('3 likes'), findsOneWidget);
  });

  testWidgets('logged-in like updates the count', (tester) async {
    final api = await _pump(
      tester,
      const User(id: 1, email: 'a@b.de', displayName: 'A'),
    );
    await tester.tap(find.byKey(const Key('like')));
    await tester.pumpAndSettle();
    expect(api.likes, 1);
    expect(find.text('4 likes'), findsOneWidget);
  });

  testWidgets('open in google maps launches the spot coordinates', (
    tester,
  ) async {
    final launched = <Uri>[];
    await _pump(
      tester,
      null,
      launcher: (u) async {
        launched.add(u);
        return true;
      },
    );
    final button = find.byKey(const Key('openInMaps'));
    expect(find.text('Open in Google Maps'), findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(launched.single, googleMapsUri(1, 2));
    // no login needed for this one
    expect(find.textContaining('login from'), findsNothing);
  });

  testWidgets('share opens the share sheet with the spot link', (tester) async {
    final shared = <(Uri, String?, Rect?)>[];
    await _pump(
      tester,
      null,
      sharer: (uri, {title, origin}) async {
        shared.add((uri, title, origin));
        return true;
      },
    );
    await tester.tap(find.byKey(const Key('shareSpot')));
    await tester.pumpAndSettle();
    final (uri, title, origin) = shared.single;
    expect(uri, spotLink(5));
    expect(title, isNotEmpty);
    expect(origin, tester.getRect(find.byKey(const Key('shareSpot'))));
    expect(find.text('Link copied'), findsNothing);
  });

  for (final fails in [false, true]) {
    testWidgets('without a share sheet the link is copied (throws: $fails)', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(
        tester,
        null,
        sharer: (_, {title, origin}) async =>
            fails ? throw StateError('no sheet') : false,
      );
      await tester.tap(find.byKey(const Key('shareSpot')));
      await tester.pumpAndSettle();
      expect(copied, spotLink(5).toString());
      expect(find.text('Link copied'), findsOneWidget);
    });
  }

  testWidgets('a failing launch shows an error instead of crashing', (
    tester,
  ) async {
    await _pump(tester, null, launcher: (_) async => false);
    final button = find.byKey(const Key('openInMaps'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('landscape phones get two panes with the map on the left', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null);
    expect(find.byKey(const Key('detailTwoPane')), findsOneWidget);
    expect(find.byKey(const Key('spotLocationMap')), findsOneWidget);
    expect(find.byType(SatelliteThumb), findsNothing); // the map replaces it
    expect(
      tester.getCenter(find.byKey(const Key('spotLocationMap'))).dx,
      lessThan(tester.getCenter(find.byKey(const Key('like'))).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone portrait without photos: the map is on top', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(tester, null);
    expect(find.byKey(const Key('detailTwoPane')), findsNothing);
    expect(find.byKey(const Key('spotCarousel')), findsNothing);
    expect(find.byType(SatelliteThumb), findsNothing);
    final map = tester.getRect(find.byKey(const Key('spotLocationMap')));
    expect(map.width, 400);
    expect(
      map.top,
      lessThan(tester.getTopLeft(find.byKey(const Key('like'))).dy),
    );
  });

  testWidgets('shows the rating next to the title', (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('spotRating')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('spotRating')),
        matching: find.text('4.5 (2)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('logged-out write review goes to login', (tester) async {
    await _pump(tester, null);
    await tester.ensureVisible(find.byKey(const Key('writeReview')));
    await tester.tap(find.byKey(const Key('writeReview')));
    await tester.pumpAndSettle();
    expect(find.text('login from null'), findsOneWidget);
  });

  testWidgets('saving a review refreshes the spot header', (tester) async {
    await _pump(tester, const User(id: 1, email: 'a@b.de', displayName: 'A'));
    await tester.ensureVisible(find.byKey(const Key('writeReview')));
    await tester.tap(find.byKey(const Key('writeReview')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reviewStar_3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('reviewSave')));
    await tester.pumpAndSettle();
    expect(reviews.calls, contains('save:3:'));
    expect(tester.takeException(), isNull);
  });

  final photoItem = feedItem(
    photos: const [
      PhotoRef(id: 1, url: 'http://x/1.jpg', thumbUrl: 'http://x/t1.jpg'),
      PhotoRef(id: 2, url: 'http://x/2.jpg', thumbUrl: 'http://x/t2.jpg'),
    ],
  );

  testWidgets('own updates can be edited and deleted after confirming', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(
      tester,
      const User(id: 1, email: 'a@b.de', displayName: 'A'),
      items: [
        photoItem,
        feedItem(id: 8, authorId: 2, body: 'other'),
      ],
    );
    await _scrollTo(tester, find.byKey(const Key('updateReport_8')));
    expect(find.byKey(const Key('updateEdit_8')), findsNothing);
    await _scrollTo(tester, find.byKey(const Key('updateDelete_7')));
    await tester.tap(find.byKey(const Key('updateDelete_7')));
    await tester.pumpAndSettle();
    expect(updates.deleted, isEmpty);
    final before = updates.listCalls;
    await tester.tap(find.byKey(const Key('updateDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(updates.deleted, [7]);
    expect(updates.listCalls, greaterThan(before));
  });

  testWidgets('editing an own update opens the composer prefilled', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(
      tester,
      const User(id: 1, email: 'a@b.de', displayName: 'A'),
      items: [feedItem(body: 'old text')],
    );
    await _scrollTo(tester, find.byKey(const Key('updateEdit_7')));
    await tester.tap(find.byKey(const Key('updateEdit_7')));
    await tester.pumpAndSettle();
    expect(find.text('old text'), findsNWidgets(2)); // tile + field
    await tester.enterText(find.byKey(const Key('updateBody')), 'new text');
    await tester.pump();
    await tester.tap(find.byKey(const Key('updateSubmit')));
    await tester.pumpAndSettle();
    expect(updates.edits.single.body, 'new text');
  });

  testWidgets('posting an update refreshes the timeline', (tester) async {
    await _pump(tester, const User(id: 1, email: 'a@b.de', displayName: 'A'));
    final before = updates.listCalls;
    await tester.ensureVisible(find.byKey(const Key('postUpdate')));
    await tester.tap(find.byKey(const Key('postUpdate')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('updateBody')), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('updateSubmit')));
    await tester.pumpAndSettle();
    expect(updates.posted.single.body, 'hello');
    expect(updates.listCalls, greaterThan(before));
  });

  testWidgets('gallery and tile photos open the viewer', (tester) async {
    _portrait(tester);
    await _pump(tester, null, items: [photoItem]);
    await tester.tap(find.byKey(const Key('galleryPhoto_0')));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photoViewerClose')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('updateTilePhoto_1')));
    await tester.tap(find.byKey(const Key('updateTilePhoto_1')));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
  });

  for (final size in const [
    Size(400, 800),
    Size(640, 360),
    Size(844, 390),
    Size(1100, 700),
    Size(1600, 1000),
  ]) {
    testWidgets('full page lays out without overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const User(id: 1, email: 'a@b.de', displayName: 'A'),
        items: [
          photoItem,
          feedItem(id: 8, authorId: 2, tag: UpdateTag.dirty),
        ],
      );
      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.byKey(const Key('reviewSummary')));
      expect(find.byKey(const Key('reviewSummary')), findsOneWidget);
      expect(find.byKey(const Key('writeReview')), findsOneWidget);
    });
  }

  testWidgets('an empty cover_url from the API does not break the spot page', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(tester, null, cover: '');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('galleryPhoto_0')), findsNothing);
    expect(find.byKey(const Key('spotLocationMap')), findsOneWidget);
  });

  testWidgets('single column: swipeable photos on top, then the map', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(tester, null, items: [photoItem]);
    final photo = tester.getRect(find.byKey(const Key('galleryPhoto_0')));
    expect(photo.width, 400);
    expect(photo.top, lessThan(tester.getTopLeft(find.text('Like')).dy));
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('spotCarousel')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byType(SatelliteThumb), findsNothing);

    // the map follows the details (positions in page coordinates)
    final page = tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    final likeY =
        tester.getTopLeft(find.text('Like')).dy + page.position.pixels;
    final map = find.byKey(const Key('spotLocationMap'));
    await _scrollTo(tester, map);
    expect(
      tester.getTopLeft(map).dy + page.position.pixels,
      greaterThan(likeY),
    );
  });

  testWidgets('two panes: the map first, then the user photos', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null, cover: 'http://test/api/v1/media/a.jpg');
    final map = tester.getTopLeft(find.byKey(const Key('spotLocationMap')));
    final photo = tester.getTopLeft(find.byKey(const Key('galleryPhoto_0')));
    expect(map.dy, lessThan(photo.dy));
    expect(find.byType(SatelliteThumb), findsNothing);
    expect(find.byKey(const Key('detailTwoPane')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side gallery: first photo large, the rest in a grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1250, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      null,
      items: [
        feedItem(
          photos: const [
            PhotoRef(id: 1, url: 'http://x/1.jpg', thumbUrl: 'http://x/t1.jpg'),
            PhotoRef(id: 2, url: 'http://x/2.jpg', thumbUrl: 'http://x/t2.jpg'),
            PhotoRef(id: 3, url: 'http://x/3.jpg', thumbUrl: 'http://x/t3.jpg'),
          ],
        ),
      ],
    );
    final first = tester.getRect(find.byKey(const Key('galleryPhoto_0')));
    final second = tester.getRect(find.byKey(const Key('galleryPhoto_1')));
    final third = tester.getRect(find.byKey(const Key('galleryPhoto_2')));
    expect(second.top, greaterThan(first.bottom));
    expect(third.top, second.top); // two columns side by side
    expect(third.left, greaterThan(second.right));
    expect(first.width, greaterThan(second.width * 2));
    // the details beside it stay at a readable width
    expect(
      tester.getSize(find.byKey(const Key('reviewSummary'))).width,
      lessThanOrEqualTo(kContentMaxWidth),
    );
  });

  testWidgets('very wide windows give the updates their own column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null, items: [feedItem(body: 'fresh paint')]);
    expect(find.byKey(const Key('detailThreePane')), findsOneWidget);
    final updates = tester.getTopLeft(find.text('Updates'));
    final like = tester.getTopLeft(find.byKey(const Key('like')));
    final reviews = tester.getTopLeft(find.text('Reviews'));
    expect(updates.dx, greaterThan(like.dx));
    expect(updates.dy, lessThan(reviews.dy)); // at the top, not below
    expect(find.text('fresh paint'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no updates yet says so', (tester) async {
    _portrait(tester);
    await _pump(tester, null, items: const []);
    await _scrollTo(tester, find.text('No updates yet'));
    expect(find.text('Updates'), findsOneWidget);
  });

  MapCamera camera(WidgetTester t) =>
      MapCamera.of(t.element(find.byType(TileLayer)));

  testWidgets('the location map shows the spot and moves with a finger', (
    tester,
  ) async {
    _portrait(tester);
    await _pump(tester, null);
    final map = find.byKey(const Key('spotLocationMap'));
    await _scrollTo(tester, map);
    expect(find.byKey(const Key('spotLocationDot')), findsOneWidget);
    expect(camera(tester).center.latitude, closeTo(1, 1e-9));
    expect(camera(tester).center.longitude, closeTo(2, 1e-9));

    final page = tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    final scrolledBefore = page.position.pixels;
    // a vertical swipe on the map pans the map, not the page
    final g = await tester.startGesture(tester.getCenter(map));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -15));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(page.position.pixels, scrolledBefore);
    expect(camera(tester).center.latitude, isNot(closeTo(1, 1e-9)));

    // and back to the spot
    await tester.tap(find.byKey(const Key('spotMapRecenter')));
    await tester.pumpAndSettle();
    expect(camera(tester).center.latitude, closeTo(1, 1e-9));

    // after letting go, the page scrolls normally again
    await tester.drag(
      find.byKey(const Key('reviewSummary')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(page.position.pixels, greaterThan(scrolledBefore));
  });

  testWidgets('the location map opens on satellite and switches to the map', (
    tester,
  ) async {
    await _pump(tester, null);
    String url() =>
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;
    // as close as the old top-down pictures
    expect(camera(tester).zoom, 19);
    expect(url(), contains('World_Imagery'));
    expect(find.text('Esri World Imagery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('spotMapLayer')));
    await tester.pumpAndSettle();
    expect(url(), isNot(contains('World_Imagery')));
    await tester.tap(find.byKey(const Key('spotMapLayer')));
    await tester.pumpAndSettle();
    expect(url(), contains('World_Imagery'));
  });

  for (final size in const [Size(844, 390), Size(1250, 800)]) {
    testWidgets('side panes: the map comes first, above the pictures, $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, null, cover: 'http://test/api/v1/media/a.jpg');
      final map = tester.getRect(find.byKey(const Key('spotLocationMap')));
      final photo = tester.getRect(find.byKey(const Key('galleryPhoto_0')));
      expect(map.bottom, lessThanOrEqualTo(photo.top));
      expect(map.left, photo.left);
      expect(tester.takeException(), isNull);
    });
  }

  const adminUser = User(
    id: 3,
    email: 'e@f.de',
    displayName: 'Ad',
    isAdmin: true,
  );

  testWidgets('admins lock and unlock the spot from the menu', (tester) async {
    final api = _Api();
    final admin = _Admin(api);
    await _pump(tester, adminUser, withApi: api, admin: admin);
    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    expect(find.text('Edit spot (admin)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('adminLockSpot')));
    await tester.pumpAndSettle();
    expect(admin.calls.single, 'spot:5:{locked: true}');
    expect(find.text('Spot locked'), findsOneWidget);
    expect(find.byKey(const Key('spotLockedNotice')), findsOneWidget);
    // admins keep every action on a locked spot
    expect(find.byKey(const Key('postUpdate')), findsOneWidget);

    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    expect(find.text('Unlock spot'), findsOneWidget);
    await tester.tap(find.byKey(const Key('adminLockSpot')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'spot:5:{locked: false}');
    expect(find.byKey(const Key('spotLockedNotice')), findsNothing);
  });

  testWidgets('the admin menu is only there for admins', (tester) async {
    await _pump(tester, const User(id: 1, email: 'a@b.de', displayName: 'A'));
    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adminEditSpot')), findsNothing);
    expect(find.byKey(const Key('adminLockSpot')), findsNothing);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('admins open the full spot editor from the spot page', (
    tester,
  ) async {
    final api = _Api();
    final admin = _Admin(api);
    await _pump(tester, adminUser, withApi: api, admin: admin);
    await tester.tap(find.byKey(const Key('menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adminEditSpot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edit-spot-owner')), findsOneWidget);
    expect(find.text('Ann'), findsWidgets); // the current owner
    await tester.enterText(
      find.byKey(const Key('edit-spot-title')),
      'New title',
    );
    await tester.tap(find.byKey(const Key('edit-spot-save')));
    await tester.pumpAndSettle();
    expect(admin.calls.single, 'spot:5:{title: New title}');
  });

  testWidgets('a locked spot: users see why and cannot post or edit', (
    tester,
  ) async {
    _portrait(tester);
    // the viewer is the spot's author and wrote update 7
    await _pump(
      tester,
      const User(id: 9, email: 'a@b.de', displayName: 'Ann'),
      locked: true,
      items: [feedItem(authorId: 9)],
    );
    expect(find.byKey(const Key('spotLockedNotice')), findsOneWidget);
    expect(
      find.text('This spot is locked. Only admins can change it.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('postUpdate')), findsNothing);
    expect(find.byKey(const Key('editTags')), findsNothing);
    await _scrollTo(tester, find.text('Updates'));
    expect(find.byKey(const Key('updateEdit_7')), findsNothing);
    expect(find.byKey(const Key('updateDelete_7')), findsNothing);
    // liking and reviewing stay open
    expect(find.byKey(const Key('like')), findsOneWidget);
  });

  testWidgets('admins edit, hide and delete other people\'s updates', (
    tester,
  ) async {
    _portrait(tester);
    final api = _Api();
    final admin = _Admin(api);
    await _pump(
      tester,
      adminUser,
      withApi: api,
      admin: admin,
      items: [feedItem(id: 8, authorId: 2, body: 'rude words')],
    );
    final menu = find.byKey(const Key('updateAdmin_8'));
    await _scrollTo(tester, menu);
    expect(find.byKey(const Key('updateReport_8')), findsNothing);

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updateAdminEdit_8')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('admin-update-body')),
      'kind words',
    );
    await tester.tap(find.byKey(const Key('admin-update-tag-dirty')));
    await tester.tap(find.byKey(const Key('admin-update-save')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'update:8:{body: kind words, tag: dirty}');

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updateAdminHide_8')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'update:8:{status: hidden}');

    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('updateAdminDelete_8')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adminUpdateDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'delete:8');
  });

  const owner = User(id: 9, email: 'a@b.de', displayName: 'Ann');
  const stranger = User(id: 2, email: 'c@d.de', displayName: 'Cy');
  const admin = User(id: 3, email: 'e@f.de', displayName: 'Ad', isAdmin: true);

  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('spot page shows tag chips, no overflow at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        owner,
        tags: const [SpotTag.roof, SpotTag.quiet, SpotTag.lit],
      );
      for (final t in const ['roof', 'quiet', 'lit']) {
        expect(find.byKey(Key('spotTag-$t')), findsOneWidget);
      }
      expect(find.byKey(const Key('spotTag-view')), findsNothing);
      expect(find.text('Roof'), findsOneWidget);
      expect(find.byKey(const Key('editTags')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('edit tags is hidden for strangers and logged-out users', (
    tester,
  ) async {
    await _pump(tester, stranger, tags: const [SpotTag.roof]);
    expect(find.byKey(const Key('spotTag-roof')), findsOneWidget);
    expect(find.byKey(const Key('editTags')), findsNothing);
  });

  testWidgets('edit tags is hidden when logged out', (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('editTags')), findsNothing);
  });

  testWidgets('an admin may edit tags of any spot', (tester) async {
    await _pump(tester, admin);
    expect(find.byKey(const Key('editTags')), findsOneWidget);
  });

  testWidgets('author edits tags: saved via the API and shown afterwards', (
    tester,
  ) async {
    final api = await _pump(tester, owner, tags: const [SpotTag.roof]);
    final btn = find.byKey(const Key('editTags'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    // roof is preselected; add water, drop roof
    await tester.tap(find.byKey(const Key('editTag-water')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('editTag-roof')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('editTagsSave')));
    await tester.pumpAndSettle();
    expect(api.savedTags, [
      [SpotTag.water],
    ]);
    expect(find.byKey(const Key('editTagsSave')), findsNothing);
    expect(find.byKey(const Key('spotTag-water')), findsOneWidget);
    expect(find.byKey(const Key('spotTag-roof')), findsNothing);
  });

  testWidgets('a forbidden answer is shown localized inside the dialog', (
    tester,
  ) async {
    final api = await _pump(tester, owner);
    api.setTagsError = ApiException(403, 'forbidden', 'nope');
    final btn = find.byKey(const Key('editTags'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editTag-view')));
    await tester.tap(find.byKey(const Key('editTagsSave')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editTagsError')), findsOneWidget);
    expect(
      find.text('Only the author or an admin can change tags'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('editTagsSave')), findsOneWidget);
  });
}
