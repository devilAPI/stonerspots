import 'package:app/core/settings.dart';
import 'package:app/features/zones/zone_consent.dart';
import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const kFavourites = 1;
const kUser = User(id: 1, email: 'a@b.de', displayName: 'A');

Spot spotNo(int id) =>
    Spot(id: id, title: 'Spot $id', lat: 48.1, lon: 11.6, likeCount: id);

class FakeAuth extends AuthController {
  FakeAuth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

/// In-memory lists, recording its calls; list [kFavourites] is the default.
class FakeSaved implements SavedRepository {
  FakeSaved({List<SpotList>? lists, Map<int, Set<int>>? items})
    : all =
          lists ??
          [
            const SpotList(
              id: kFavourites,
              name: 'Favourites',
              isDefault: true,
            ),
          ],
      items = items ?? {};

  final List<SpotList> all;

  /// Spot ids by list.
  final Map<int, Set<int>> items;
  final calls = <String>[];
  Object? failWrites;
  Object? failSpots;
  int pageSize = 100;
  int _nextId = 10;

  Set<int> _in(int spotId) => {
    for (final e in items.entries)
      if (e.value.contains(spotId)) e.key,
  };

  void _write(String call) {
    calls.add(call);
    if (failWrites != null) throw failWrites!;
  }

  @override
  Future<List<SpotList>> lists() async {
    calls.add('lists');
    return [
      for (final l in all)
        SpotList(
          id: l.id,
          name: l.name,
          isDefault: l.isDefault,
          coverUrl: l.coverUrl,
          spotCount: items[l.id]?.length ?? 0,
        ),
    ];
  }

  @override
  Future<SpotList> getList(int id) async =>
      (await lists()).firstWhere((l) => l.id == id);

  @override
  Future<SpotList> create(String name) async {
    _write('create:$name');
    final list = SpotList(id: _nextId++, name: name);
    all.add(list);
    return list;
  }

  @override
  Future<SpotList> rename(int id, String name) async {
    _write('rename:$id:$name');
    final i = all.indexWhere((l) => l.id == id);
    return all[i] = SpotList(id: id, name: name);
  }

  @override
  Future<void> deleteList(int id) async {
    _write('delete:$id');
    all.removeWhere((l) => l.id == id);
    items.remove(id);
  }

  @override
  Future<CursorPage<Spot>> spots(int listId, {String? cursor}) async {
    calls.add('spots:$listId:${cursor ?? ''}');
    if (failSpots != null) throw failSpots!;
    final ids = (items[listId] ?? const <int>{}).toList();
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, ids.length);
    return CursorPage(
      ids.sublist(start, end).map(spotNo).toList(),
      end < ids.length ? '$end' : null,
    );
  }

  @override
  Future<Set<int>> membership(int spotId) async {
    calls.add('membership:$spotId');
    return _in(spotId);
  }

  @override
  Future<Set<int>> saveToFavourites(int spotId) async {
    _write('favourite:$spotId');
    (items[kFavourites] ??= {}).add(spotId);
    return _in(spotId);
  }

  @override
  Future<Set<int>> addSpot(int listId, int spotId) async {
    _write('add:$listId:$spotId');
    (items[listId] ??= {}).add(spotId);
    return _in(spotId);
  }

  @override
  Future<Set<int>> removeSpot(int listId, int spotId) async {
    _write('remove:$listId:$spotId');
    items[listId]?.remove(spotId);
    return _in(spotId);
  }
}

void portrait(WidgetTester t, [Size size = const Size(400, 800)]) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

/// Pumps [routes] (plus a login page) starting at [initial].
Future<GoRouter> pumpSaved(
  WidgetTester t,
  FakeSaved repo, {
  required List<RouteBase> routes,
  required String initial,
  User? user = kUser,
  Locale locale = const Locale('en'),
  List<Override> overrides = const [],
}) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      ...routes,
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
        // zones (and their first-use disclaimer) are tested in test/zones
        zonesEnabledProvider.overrideWith(() => BoolSetting('zones_enabled')),
        savedRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => FakeAuth(user)),
        ...overrides,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
  return router;
}
