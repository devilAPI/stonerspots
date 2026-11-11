import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/users/user_profile_screen.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const kMe = User(id: 1, email: 'me@x.de', displayName: 'Me');

class FakeAuth extends AuthController {
  FakeAuth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

Spot spotNo(int id) => Spot(id: id, title: 'Spot $id', lat: 48.1, lon: 11.6);

FeedItem updateNo(int id, {int author = 7, String name = 'Alice'}) => FeedItem(
  id: id,
  body: 'update $id',
  photos: const [],
  createdAt: DateTime(2026, 1, 1),
  author: Author(id: author, displayName: name),
  spot: Spot(id: 100 + id, title: 'Spot ${100 + id}', lat: 48, lon: 11),
);

/// In-memory profiles, recording its calls. Lists come in pages of
/// [pageSize]; cursors are offsets.
class FakeUsers implements UsersRepository {
  FakeUsers({
    Map<int, UserProfile>? profiles,
    this.spotIds = const [],
    this.updateIds = const [],
  }) : profiles =
           profiles ??
           {
             7: UserProfile(
               id: 7,
               displayName: 'Alice',
               createdAt: DateTime.utc(2025, 3, 15),
               spotCount: 2,
               updateCount: 3,
               followerCount: 4,
               followingCount: 5,
             ),
           };

  final Map<int, UserProfile> profiles;
  final List<int> spotIds;
  final List<int> updateIds;
  final calls = <String>[];
  int pageSize = 100;
  Object? failFollow;

  @override
  Future<UserProfile> profile(int id) async {
    calls.add('profile:$id');
    final p = profiles[id];
    if (p == null) throw ApiException(404, 'not_found', 'user not found');
    return p;
  }

  CursorPage<T> _page<T>(List<int> ids, String? cursor, T Function(int) f) {
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, ids.length);
    return CursorPage(
      ids.sublist(start, end).map(f).toList(),
      end < ids.length ? '$end' : null,
    );
  }

  @override
  Future<CursorPage<Spot>> spots(int id, {String? cursor}) async {
    calls.add('spots:$id:${cursor ?? ''}');
    return _page(spotIds, cursor, spotNo);
  }

  @override
  Future<CursorPage<FeedItem>> updates(int id, {String? cursor}) async {
    calls.add('updates:$id:${cursor ?? ''}');
    return _page(updateIds, cursor, (u) => updateNo(u, author: id));
  }

  @override
  Future<void> follow(int id) async {
    calls.add('follow:$id');
    if (failFollow != null) throw failFollow!;
  }

  @override
  Future<void> unfollow(int id) async {
    calls.add('unfollow:$id');
    if (failFollow != null) throw failFollow!;
  }

  Object? failBio;

  @override
  Future<String> setBio(String bio) async {
    calls.add('bio:$bio');
    if (failBio != null) throw failBio!;
    return bio.trim();
  }
}

void portrait(WidgetTester t, [Size size = const Size(400, 800)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Pumps the profile of [userId] on top of a home page, with stand-ins for
/// the pages it links to.
Future<GoRouter> pumpProfile(
  WidgetTester t,
  FakeUsers repo, {
  int userId = 7,
  User? user = kMe,
  Locale locale = const Locale('en'),
  // extra MediaQuery padding, e.g. the navigation rail on wide windows
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home page')),
      ),
      GoRoute(
        path: '/user/:id',
        builder: (_, s) =>
            UserProfileScreen(userId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('login page')),
      ),
      GoRoute(
        path: '/spot/:id',
        builder: (_, s) =>
            Scaffold(body: Text('spot page ${s.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        usersRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => FakeAuth(user)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: MediaQuery.paddingOf(context) + padding),
          child: child!,
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
  router.push('/user/$userId');
  await t.pumpAndSettle();
  return router;
}
