import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/reviews/reviews_repository.dart';
import 'package:app/features/reviews/reviews_section.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'review_helpers.dart';

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

const me = User(id: 1, email: 'a@b.de', displayName: 'Me');

Future<({List<int> reported, List<String> events})> pump(
  WidgetTester t,
  FakeReviews repo, {
  User? user = me,
  bool gateBlocks = false,
}) async {
  final reported = <int>[];
  final events = <String>[];
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        reviewsRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => _Auth(user)),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReviewsSection(
              spotId: 5,
              gate: (a) {
                events.add('gate');
                if (!gateBlocks) a();
              },
              onReport: reported.add,
              onChanged: () => events.add('changed'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (reported: reported, events: events);
}

ReviewsPage page({
  Map<int, int> dist = const {},
  Review? mine,
  List<Review> items = const [],
  String? next,
}) => ReviewsPage(
  summary: summaryOf(dist),
  mine: mine,
  items: items,
  nextCursor: next,
);

void main() {
  testWidgets('empty state', (t) async {
    await pump(t, FakeReviews([page()]));
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('Write a review'), findsOneWidget);
  });

  testWidgets('summary shows average, count and five bars', (t) async {
    await pump(
      t,
      FakeReviews([
        page(dist: {4: 3, 5: 1}, items: [review(1)]),
      ]),
    );
    expect(find.text('4.3'), findsOneWidget);
    expect(find.text('4 reviews'), findsOneWidget);
    for (var i = 1; i <= 5; i++) {
      expect(find.byKey(Key('reviewDistBar_$i')), findsOneWidget);
    }
    expect(find.text('No reviews yet'), findsNothing);
  });

  testWidgets('own review: label, edit and delete; others: report', (t) async {
    final mine = review(2, authorId: 1, name: 'Me', body: 'mine!');
    final env = await pump(
      t,
      FakeReviews([
        page(
          dist: {4: 2},
          mine: mine,
          items: [
            mine,
            review(3, body: 'theirs'),
          ],
        ),
      ]),
    );
    expect(find.text('Edit your review'), findsOneWidget);
    expect(find.textContaining('Your review'), findsOneWidget);
    expect(find.byKey(const Key('reviewEdit_2')), findsOneWidget);
    expect(find.byKey(const Key('reviewDelete_2')), findsOneWidget);
    expect(find.byKey(const Key('reviewReport_2')), findsNothing);
    expect(find.byKey(const Key('reviewReport_3')), findsOneWidget);
    expect(find.byKey(const Key('reviewEdit_3')), findsNothing);
    await t.tap(find.byKey(const Key('reviewReport_3')));
    expect(env.reported, [3]);
  });

  testWidgets('edited hint when updatedAt is later', (t) async {
    await pump(
      t,
      FakeReviews([
        page(
          dist: {4: 1},
          items: [review(1, updated: DateTime(2026, 10, 5))],
        ),
      ]),
    );
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('write button is login gated', (t) async {
    final env = await pump(
      t,
      FakeReviews([page()]),
      user: null,
      gateBlocks: true,
    );
    await t.tap(find.byKey(const Key('writeReview')));
    await t.pumpAndSettle();
    expect(env.events, ['gate']);
    expect(find.byKey(const Key('reviewSave')), findsNothing);
  });

  testWidgets('saving refreshes the list and notifies', (t) async {
    final repo = FakeReviews([
      page(),
      page(dist: {5: 1}, mine: review(99, authorId: 1, rating: 5)),
    ]);
    final env = await pump(t, repo);
    await t.tap(find.byKey(const Key('writeReview')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('reviewStar_5')));
    await t.pump();
    await t.tap(find.byKey(const Key('reviewSave')));
    await t.pumpAndSettle();
    expect(repo.calls, ['list:', 'save:5:', 'list:']);
    expect(env.events, contains('changed'));
    expect(find.text('Edit your review'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation', (t) async {
    final mine = review(2, authorId: 1, name: 'Me');
    final repo = FakeReviews([
      page(dist: {4: 1}, mine: mine, items: [mine]),
      page(),
    ]);
    final env = await pump(t, repo);
    await t.tap(find.byKey(const Key('reviewDelete_2')));
    await t.pumpAndSettle();
    expect(repo.calls, ['list:']);
    await t.tap(find.byKey(const Key('reviewDeleteConfirm')));
    await t.pumpAndSettle();
    expect(repo.calls, ['list:', 'delete', 'list:']);
    expect(env.events, contains('changed'));
    expect(find.text('No reviews yet'), findsOneWidget);
  });

  testWidgets('load more appends the next page', (t) async {
    final repo = FakeReviews(
      [
        page(
          dist: {4: 2},
          items: [review(1, body: 'first')],
          next: 'c1',
        ),
      ],
      more: page(
        dist: {4: 2},
        items: [review(2, body: 'second')],
      ),
    );
    await pump(t, repo);
    expect(find.text('first'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('reviewMore')));
    await t.tap(find.byKey(const Key('reviewMore')));
    await t.pumpAndSettle();
    expect(repo.calls.last, 'list:c1');
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.byKey(const Key('reviewMore')), findsNothing);
  });
}
