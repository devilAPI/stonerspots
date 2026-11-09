import 'package:app/core/api_client.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'users_helpers.dart';

Finder _tab(String label) => find.descendant(
  of: find.byKey(const Key('userTabs')),
  matching: find.text(label),
);

String _stat(WidgetTester t, String key) => t
    .widgetList<Text>(
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)),
    )
    .first
    .data!;

void main() {
  testWidgets('shows name, join date and counts', (t) async {
    portrait(t);
    await pumpProfile(t, FakeUsers(spotIds: [1, 2]));
    expect(find.byKey(const Key('userName')), findsOneWidget);
    expect(find.text('Alice'), findsWidgets);
    expect(find.text('Joined March 2025'), findsOneWidget);
    expect(_stat(t, 'statSpots'), '2');
    expect(_stat(t, 'statUpdates'), '3');
    expect(_stat(t, 'statFollowers'), '4');
    expect(_stat(t, 'statFollowing'), '5');
    expect(find.text('Followers'), findsOneWidget);
    expect(find.byKey(const Key('followButton')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('German strings', (t) async {
    portrait(t);
    await pumpProfile(t, FakeUsers(), locale: const Locale('de'));
    expect(find.text('Dabei seit März 2025'), findsOneWidget);
    expect(find.text('Folgen'), findsOneWidget);
    expect(find.text('Follower'), findsOneWidget);
    expect(find.text('Noch keine Spots'), findsOneWidget);
  });

  testWidgets('follow and unfollow update the button and the count', (t) async {
    portrait(t);
    final repo = FakeUsers();
    await pumpProfile(t, repo);

    await t.tap(find.byKey(const Key('followButton')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('follow:7'));
    expect(find.byKey(const Key('unfollowButton')), findsOneWidget);
    expect(_stat(t, 'statFollowers'), '5');

    await t.tap(find.byKey(const Key('unfollowButton')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('unfollow:7'));
    expect(find.byKey(const Key('followButton')), findsOneWidget);
    expect(_stat(t, 'statFollowers'), '4');
  });

  testWidgets('a failed follow is undone and says so', (t) async {
    portrait(t);
    final repo = FakeUsers()..failFollow = ApiException(500, 'internal', 'x');
    await pumpProfile(t, repo);
    await t.tap(find.byKey(const Key('followButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('followButton')), findsOneWidget);
    expect(_stat(t, 'statFollowers'), '4');
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('no follow button on your own profile', (t) async {
    portrait(t);
    final repo = FakeUsers(
      profiles: {
        1: UserProfile(
          id: 1,
          displayName: 'Me',
          createdAt: DateTime.utc(2025),
          isMe: true,
        ),
      },
    );
    await pumpProfile(t, repo, userId: 1);
    expect(find.byKey(const Key('followButton')), findsNothing);
    expect(find.byKey(const Key('unfollowButton')), findsNothing);
  });

  testWidgets('logged out: follow opens the login page', (t) async {
    portrait(t);
    final repo = FakeUsers();
    await pumpProfile(t, repo, user: null);
    await t.tap(find.byKey(const Key('followButton')));
    await t.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('follow')), isEmpty);
  });

  testWidgets('unknown users show that the profile does not exist', (t) async {
    portrait(t);
    await pumpProfile(t, FakeUsers(), userId: 99);
    expect(find.text('This profile does not exist'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('spots and updates tabs, each paging on scroll', (t) async {
    portrait(t);
    final repo = FakeUsers(
      spotIds: [for (var i = 1; i <= 30; i++) i],
      updateIds: [for (var i = 1; i <= 3; i++) i],
    )..pageSize = 20;
    final router = await pumpProfile(t, repo);
    expect(find.byKey(const Key('userSpot-1')), findsOneWidget);
    expect(repo.calls, contains('spots:7:'));
    expect(repo.calls, contains('updates:7:'));

    await t.tap(_tab('Updates'));
    await t.pumpAndSettle();
    expect(find.byType(FeedCard), findsWidgets);
    expect(find.text('update 1'), findsOneWidget);
    expect(find.byKey(const Key('userSpot-1')), findsNothing);
    // the author is this profile's user: plain text, no link to itself
    expect(find.byKey(const Key('authorLink-7')), findsNothing);

    await t.tap(find.text('Spot 101'));
    await t.pumpAndSettle();
    expect(find.text('spot page 101'), findsOneWidget);
    router.pop();
    await t.pumpAndSettle();

    await t.tap(_tab('Spots'));
    await t.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'spots:7:'), hasLength(1));
    await t.scrollUntilVisible(
      find.byKey(const Key('userSpot-30')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(repo.calls, contains('spots:7:20'));
    expect(t.takeException(), isNull);
  });

  testWidgets('spot rows: no credit in the thumbnails, once below them', (
    t,
  ) async {
    portrait(t);
    await pumpProfile(t, FakeUsers(spotIds: [1, 2, 3]));
    expect(find.byKey(const Key('userSpot-1')), findsOneWidget);
    // "Esri World Imagery" cut to "…ld Imagery" in every 56 px thumbnail
    expect(find.text('Esri World Imagery'), findsNothing);
    expect(find.byKey(const Key('satelliteCredit')), findsOneWidget);
    expect(find.text('Satellite images: Esri World Imagery'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('landscape phones: update cards put the picture beside', (
    t,
  ) async {
    portrait(t, const Size(844, 390));
    await pumpProfile(t, FakeUsers(spotIds: [1, 2], updateIds: [1, 2]));
    // spot rows stay compact
    expect(t.getSize(find.byKey(const Key('userSpot-1'))).height, 72);

    await t.tap(_tab('Updates'));
    await t.pumpAndSettle();
    final card = find.byType(FeedCard).first;
    expect(t.widget<FeedCard>(card).layout, FeedCardLayout.side);
    // a whole card fits the short screen
    expect(t.getSize(card).height, lessThan(390 / 2));
    expect(t.takeException(), isNull);
  });

  testWidgets('portrait phones keep the picture on top', (t) async {
    portrait(t);
    await pumpProfile(t, FakeUsers(updateIds: [1]));
    await t.tap(_tab('Updates'));
    await t.pumpAndSettle();
    expect(
      t.widget<FeedCard>(find.byType(FeedCard)).layout,
      FeedCardLayout.stacked,
    );
  });

  testWidgets('empty lists say so', (t) async {
    portrait(t);
    await pumpProfile(t, FakeUsers());
    expect(find.text('No spots yet'), findsOneWidget);
    await t.tap(_tab('Updates'));
    await t.pumpAndSettle();
    expect(find.text('No updates yet'), findsOneWidget);
  });

  testWidgets('lays out without overflow on wide windows', (t) async {
    portrait(t, const Size(1400, 900));
    await pumpProfile(t, FakeUsers(spotIds: [1, 2, 3]));
    expect(find.byKey(const Key('userSpot-3')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
