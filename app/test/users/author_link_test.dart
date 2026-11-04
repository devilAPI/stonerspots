import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:app/features/reviews/reviews_repository.dart';
import 'package:app/features/reviews/reviews_section.dart';
import 'package:app/features/spots/update_tile.dart';
import 'package:app/features/users/author_link.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../reviews/review_helpers.dart';
import 'users_helpers.dart';

/// Pumps [child] on a page that can open profiles.
Future<void> _pump(WidgetTester t, Widget child, {FakeReviews? reviews}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) =>
            Scaffold(body: Text('profile ${s.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/spot/:id',
        builder: (_, s) =>
            Scaffold(body: Text('spot ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => FakeAuth(kMe)),
        if (reviews != null)
          reviewsRepositoryProvider.overrideWithValue(reviews),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the author on a feed card opens their profile', (t) async {
    await _pump(t, FeedCard(item: updateNo(3, author: 7, name: 'Alice')));
    expect(find.text('Alice'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('authorLink-7')));
    await t.tap(find.byKey(const Key('authorLink-7')));
    await t.pumpAndSettle();
    expect(find.text('profile 7'), findsOneWidget);
  });

  testWidgets('the author of an update tile opens their profile', (t) async {
    await _pump(
      t,
      UpdateTile(
        item: updateNo(3, author: 8, name: 'Bob'),
        isMine: false,
        onEdit: () {},
        onDelete: () {},
        onReport: () {},
        onPhotoTap: (_) {},
      ),
    );
    expect(find.text('Bob'), findsOneWidget);
    await t.tap(find.byKey(const Key('authorLink-8')));
    await t.pumpAndSettle();
    expect(find.text('profile 8'), findsOneWidget);
  });

  testWidgets('the author of a review opens their profile', (t) async {
    final repo = FakeReviews([
      ReviewsPage(
        summary: summaryOf({4: 1}),
        mine: null,
        items: [review(1, authorId: 9, name: 'Bo')],
        nextCursor: null,
      ),
    ]);
    await _pump(
      t,
      ReviewsSection(spotId: 5, gate: (a) => a(), onReport: (_) {}),
      reviews: repo,
    );
    expect(find.text('Bo'), findsOneWidget);
    await t.tap(find.byKey(const Key('authorLink-9')));
    await t.pumpAndSettle();
    expect(find.text('profile 9'), findsOneWidget);
  });

  testWidgets('on that author\'s own profile the name is plain text', (
    t,
  ) async {
    await _pump(
      t,
      ProfileScope(
        userId: 7,
        child: Column(
          children: [
            AuthorLink(author: const Author(id: 7, displayName: 'Alice')),
            AuthorLink(author: const Author(id: 8, displayName: 'Bob')),
          ],
        ),
      ),
    );
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byKey(const Key('authorLink-7')), findsNothing);
    expect(find.byKey(const Key('authorLink-8')), findsOneWidget);
  });
}
