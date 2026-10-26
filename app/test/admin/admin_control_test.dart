import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/tag_catalog.dart';
import 'package:app/features/admin/admin_edit_dialogs.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/admin/admin_tags_tab.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AdminUser _user(int id) => AdminUser(
  id: id,
  email: 'user$id@x.de',
  displayName: 'User$id',
  isAdmin: false,
  createdAt: DateTime.utc(2026),
  spotCount: 0,
  reportsReceived: 0,
);

final _spot = AdminSpot(
  id: 7,
  title: 'Bench',
  lat: 48.5,
  lon: 11.25,
  status: 'active',
  likeCount: 0,
  createdAt: DateTime.utc(2026),
  author: const Author(id: 1, displayName: 'User1'),
  reportCount: 0,
);

/// In-memory admin API for the owner / lock / tag catalog features.
class _Fake implements AdminRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  final spotPatches = <Map<String, dynamic>>[];
  final userQueries = <String?>[];
  List<AdminTag> catalog = [
    for (final t in SpotTag.builtIn)
      AdminTag(t, spotCount: t == SpotTag.roof ? 3 : 0),
  ];
  final tagCalls = <String>[];
  ApiException? createError;

  @override
  Future<AdminPage<AdminUser>> users({
    String? q,
    String? cursor,
    int limit = 20,
  }) async {
    userQueries.add(q);
    final all = [for (var i = 1; i <= 3; i++) _user(i)];
    return AdminPage([
      for (final u in all)
        if (q == null || u.displayName.contains(q)) u,
    ], null);
  }

  @override
  Future<AdminSpot> updateSpot(int id, AdminSpotPatch patch) async {
    spotPatches.add(patch.toJson());
    return _spot;
  }

  @override
  Future<List<AdminTag>> tags() async => List.of(catalog);

  @override
  Future<SpotTag> createTag(AdminTagDraft draft) async {
    tagCalls.add('create:${draft.toJson()}');
    if (createError != null) throw createError!;
    final t = SpotTag(
      draft.tag!,
      nameDe: draft.nameDe!,
      nameEn: draft.nameEn!,
      icon: draft.icon!,
      sort: 999,
    );
    catalog = [...catalog, AdminTag(t)];
    return t;
  }

  @override
  Future<SpotTag> updateTag(String tag, AdminTagDraft draft) async {
    tagCalls.add('update:$tag:${draft.toJson()}');
    catalog = [
      for (final a in catalog)
        if (a.tag.wire == tag)
          AdminTag(
            SpotTag(
              tag,
              nameDe: draft.nameDe ?? a.tag.nameDe,
              nameEn: draft.nameEn ?? a.tag.nameEn,
              icon: draft.icon ?? a.tag.icon,
              sort: draft.sort ?? a.tag.sort,
            ),
            spotCount: a.spotCount,
          )
        else
          a,
    ]..sort((a, b) => a.tag.sort.compareTo(b.tag.sort));
    return catalog.firstWhere((a) => a.tag.wire == tag).tag;
  }

  @override
  Future<void> deleteTag(String tag) async {
    tagCalls.add('delete:$tag');
    catalog = [
      for (final a in catalog)
        if (a.tag.wire != tag) a,
    ];
  }
}

Future<ProviderContainer> _pump(WidgetTester t, _Fake repo, Widget home) async {
  addTearDown(SpotTag.resetCatalog);
  t.view.physicalSize = const Size(800, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    ),
  );
  await t.pumpAndSettle();
  return ProviderScope.containerOf(t.element(find.byType(Scaffold)));
}

void main() {
  testWidgets('edit spot dialog: change the owner and lock the spot', (
    t,
  ) async {
    final repo = _Fake();
    AdminSpot? result;
    await _pump(
      t,
      repo,
      Builder(
        builder: (c) => TextButton(
          onPressed: () async =>
              result = await showEditSpotDialog(c, spot: _spot),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('User1'), findsOneWidget); // current owner

    await t.tap(find.byKey(const Key('edit-spot-change-owner')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('owner-pick-3')), findsOneWidget);
    await t.enterText(find.byKey(const Key('owner-search')), 'User2');
    await t.pumpAndSettle();
    expect(repo.userQueries.last, 'User2');
    expect(find.byKey(const Key('owner-pick-3')), findsNothing);
    await t.tap(find.byKey(const Key('owner-pick-2')));
    await t.pumpAndSettle();
    expect(find.text('User2'), findsOneWidget);

    await t.tap(find.byKey(const Key('edit-spot-status-locked')));
    await t.pump();
    await t.tap(find.byKey(const Key('edit-spot-save')));
    await t.pumpAndSettle();
    expect(repo.spotPatches.single, {'owner_id': 2, 'locked': true});
    expect(result, isNotNull);
  });

  testWidgets('edit spot dialog: unchanged owner and lock are not sent', (
    t,
  ) async {
    final repo = _Fake();
    await _pump(
      t,
      repo,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => showEditSpotDialog(c, spot: _spot),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('edit-spot-title')), 'Renamed');
    await t.tap(find.byKey(const Key('edit-spot-save')));
    await t.pumpAndSettle();
    expect(repo.spotPatches.single, {'title': 'Renamed'});
  });

  testWidgets('tags tab lists the catalog with spot counts', (t) async {
    final repo = _Fake();
    final c = await _pump(t, repo, const AdminTagsTab());
    expect(find.byKey(const Key('admin-tag-roof')), findsOneWidget);
    expect(find.text('roof · 3 spots'), findsOneWidget);
    expect(find.text('lit · no spots'), findsOneWidget);
    // the app-wide catalog follows what the server says
    expect(c.read(tagCatalogProvider).length, 7);
  });

  testWidgets('create a tag: it shows up in the app catalog', (t) async {
    final repo = _Fake();
    final c = await _pump(t, repo, const AdminTagsTab());
    await t.tap(find.byKey(const Key('tag-new')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('tag-key')), 'fire_pit');
    await t.enterText(find.byKey(const Key('tag-name-de')), 'Feuerstelle');
    await t.enterText(find.byKey(const Key('tag-name-en')), 'Fire pit');
    await t.tap(find.byKey(const Key('tag-icon-fire')));
    await t.tap(find.byKey(const Key('tag-save')));
    await t.pumpAndSettle();
    expect(repo.tagCalls.single, contains('tag: fire_pit'));
    expect(repo.tagCalls.single, contains('icon: fire'));
    expect(find.byKey(const Key('admin-tag-fire_pit')), findsOneWidget);
    expect(c.read(tagCatalogProvider).map((t) => t.wire), contains('fire_pit'));
    expect(SpotTag.of('fire_pit').nameEn, 'Fire pit');
  });

  testWidgets('create errors are shown in the dialog', (t) async {
    final repo = _Fake()..createError = ApiException(409, 'tag_taken', 'taken');
    await _pump(t, repo, const AdminTagsTab());
    await t.tap(find.byKey(const Key('tag-new')));
    await t.pumpAndSettle();
    // names are required before anything is sent
    await t.tap(find.byKey(const Key('tag-save')));
    await t.pumpAndSettle();
    expect(find.text('Names must be 1 to 40 characters'), findsOneWidget);
    expect(repo.tagCalls, isEmpty);

    await t.enterText(find.byKey(const Key('tag-key')), 'roof');
    await t.enterText(find.byKey(const Key('tag-name-de')), 'Dach');
    await t.enterText(find.byKey(const Key('tag-name-en')), 'Roof');
    await t.tap(find.byKey(const Key('tag-save')));
    await t.pumpAndSettle();
    expect(find.text('A tag with this key already exists'), findsOneWidget);
    expect(find.byKey(const Key('tag-save')), findsOneWidget); // still open
  });

  testWidgets('rename a tag: only changed fields are sent, key is fixed', (
    t,
  ) async {
    final repo = _Fake();
    await _pump(t, repo, const AdminTagsTab());
    await t.tap(find.byKey(const Key('tag-edit-quiet')));
    await t.pumpAndSettle();
    final key = t.widget<TextField>(find.byKey(const Key('tag-key')));
    expect(key.enabled, isFalse);
    await t.enterText(find.byKey(const Key('tag-name-en')), 'Silent');
    await t.tap(find.byKey(const Key('tag-save')));
    await t.pumpAndSettle();
    expect(repo.tagCalls.single, 'update:quiet:{name_en: Silent}');
    expect(find.text('Ruhig · Silent'), findsOneWidget);
  });

  testWidgets('move a tag down swaps it with the next one', (t) async {
    final repo = _Fake();
    final c = await _pump(t, repo, const AdminTagsTab());
    expect(find.byKey(const Key('tag-up-roof')), findsOneWidget);
    expect(
      t.widget<IconButton>(find.byKey(const Key('tag-up-roof'))).onPressed,
      isNull, // first one cannot go up
    );
    await t.tap(find.byKey(const Key('tag-down-roof')));
    await t.pumpAndSettle();
    expect(repo.tagCalls, [
      'update:roof:{sort: 20}',
      'update:seating:{sort: 10}',
    ]);
    expect(c.read(tagCatalogProvider).take(2).map((t) => t.wire), [
      'seating',
      'roof',
    ]);
  });

  testWidgets('delete a tag after confirming; the count is shown', (t) async {
    final repo = _Fake();
    final c = await _pump(t, repo, const AdminTagsTab());
    await t.tap(find.byKey(const Key('tag-delete-roof')));
    await t.pumpAndSettle();
    expect(find.text('It is removed from 3 spots.'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.tagCalls, isEmpty);

    await t.tap(find.byKey(const Key('tag-delete-roof')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-delete-tag')));
    await t.pumpAndSettle();
    expect(repo.tagCalls, ['delete:roof']);
    expect(find.byKey(const Key('admin-tag-roof')), findsNothing);
    expect(c.read(tagCatalogProvider), isNot(contains(SpotTag.roof)));
  });
}
