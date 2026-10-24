import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/spot_detail_screen.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Api implements SpotApi {
  int likes = 0;

  @override
  Future<Spot> getSpot(int id) async =>
      const Spot(id: 5, title: 'Lake bench', category: 'lake', lat: 1, lon: 2, likeCount: 3);
  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) async {
    likes++;
    return const LikeResult(liked: true, likeCount: 4);
  }

  @override
  Future<Spot> createSpot(SpotDraft d, {bool force = false}) =>
      throw UnimplementedError();
  @override
  Future<void> report(String t, int id, String r) async {}
}

class _Updates implements UpdatesRepository {
  @override
  Future<List<FeedItem>> listForSpot(int spotId) async => [];
  @override
  Future<void> post(int spotId,
      {required String body, List<int> photoIds = const []}) async {}
}

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

Future<_Api> _pump(WidgetTester tester, User? user) async {
  final api = _Api();
  final router = GoRouter(initialLocation: '/spot/5', routes: [
    GoRoute(
        path: '/spot/:id',
        builder: (_, _) => const SpotDetailScreen(spotId: 5)),
    GoRoute(
        path: '/login',
        builder: (_, s) =>
            Scaffold(body: Text('login from ${s.uri.queryParameters['from']}'))),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      spotApiProvider.overrideWithValue(api),
      spotUpdatesRepositoryProvider.overrideWithValue(_Updates()),
      authControllerProvider.overrideWith(() => _Auth(user)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

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
        tester, const User(id: 1, email: 'a@b.de', displayName: 'A'));
    await tester.tap(find.byKey(const Key('like')));
    await tester.pumpAndSettle();
    expect(api.likes, 1);
    expect(find.text('4 likes'), findsOneWidget);
  });
}
