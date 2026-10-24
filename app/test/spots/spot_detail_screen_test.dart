import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/spots/maps_link.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/spot_detail_screen.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/reviews/reviews_repository.dart';
import 'package:app/features/spots/photo_viewer.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../reviews/review_helpers.dart';
import 'update_helpers.dart';

class _Api implements SpotApi {
  _Api({this.cover, this.tags = const [], this.authorId = 9});
  final String? cover;
  int likes = 0;
  List<SpotTag> tags;
  final int authorId;
  final savedTags = <List<SpotTag>>[];
  Object? setTagsError;

  @override
  Future<Spot> getSpot(int id) async => Spot(
    id: 5,
    title: 'Lake bench',
    category: 'lake',
    lat: 1,
    lon: 2,
    likeCount: 3,
    coverUrl: cover,
    ratingAvg: 4.5,
    ratingCount: 2,
    tags: tags,
    author: Author(id: authorId, displayName: 'Ann'),
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
}) async {
  final api = withApi ?? _Api(cover: cover, tags: tags, authorId: authorId);
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

/// The page is a lazy list: scroll the main (first) scrollable to [f].
Future<void> _scrollTo(WidgetTester t, Finder f) =>
    t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first);

void main() {
  testWidgets('logged-out like goes to login with from', (tester) async {
    final api = await _pump(tester, null);
    expect(find.text('3 likes'), findsOneWidget);
    await tester.tap(find.byKey(const Key('like')));
    await tester.pumpAndSettle();
    expect(find.text('login from /spot/5'), findsOneWidget);
    expect(api.likes, 0);
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

  testWidgets(
    'wide windows and landscape phones get two panes with a satellite view',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, null);
      expect(find.byKey(const Key('detailTwoPane')), findsOneWidget);
      // no photos yet -> the left pane shows the spot from above
      expect(find.byType(SatelliteThumb), findsOneWidget);
      expect(find.text('Lake bench'), findsWidgets);
      expect(find.byKey(const Key('like')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone portrait stays a single column', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null);
    expect(find.byKey(const Key('detailTwoPane')), findsNothing);
    expect(find.byKey(const Key('like')), findsOneWidget);
    // no user photos -> the spot is shown from above
    expect(find.byType(SatelliteThumb), findsOneWidget);
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
    expect(find.text('login from /spot/5'), findsOneWidget);
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

  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
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
      expect(find.byKey(const Key('reviewSummary')), findsOneWidget);
      expect(find.byKey(const Key('writeReview')), findsOneWidget);
    });
  }

  testWidgets('an empty cover_url from the API does not break the spot page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null, cover: '');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('satelliteTile')), findsOneWidget);
    expect(find.byKey(const Key('galleryPhoto_0')), findsNothing);
  });

  testWidgets('single column: user photos first, then the top-down view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null, cover: 'http://test/api/v1/media/a.jpg');
    final photo = tester.getTopLeft(find.byKey(const Key('galleryPhoto_0')));
    final sat = tester.getTopLeft(find.byKey(const Key('satelliteTile')));
    expect(photo.dx, lessThan(sat.dx));
    expect(find.byType(SatelliteThumb), findsOneWidget);
  });

  testWidgets('two panes: user photos first, then the top-down view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, null, cover: 'http://test/api/v1/media/a.jpg');
    final photo = tester.getTopLeft(find.byKey(const Key('galleryPhoto_0')));
    final sat = tester.getTopLeft(find.byKey(const Key('satelliteTile')));
    expect(photo.dy, lessThan(sat.dy));
    expect(find.byKey(const Key('detailTwoPane')), findsOneWidget);
    expect(tester.takeException(), isNull);
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
