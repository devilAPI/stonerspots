import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/feed/feed_card.dart';
import 'package:app/features/spots/update_actions.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../spots/update_helpers.dart';

class _Auth extends AuthController {
  _Auth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

class _Admin implements AdminRepository {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> updateUpdate(int id, AdminUpdatePatch patch) async =>
      calls.add('update:$id:${patch.toJson()}');
}

const _ann = User(id: 1, email: 'a@b.de', displayName: 'Ann');
const _cy = User(id: 2, email: 'c@d.de', displayName: 'Cy');
const _admin = User(id: 3, email: 'e@f.de', displayName: 'Ad', isAdmin: true);

late FakeUpdates _updates;
late _Admin _adminRepo;
late int _changes;

Future<void> _pump(WidgetTester t, User? user, FeedItem item) async {
  _updates = FakeUpdates(items: [item]);
  _adminRepo = _Admin();
  _changes = 0;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _Auth(user)),
        spotUpdatesRepositoryProvider.overrideWithValue(_updates),
        adminRepositoryProvider.overrideWithValue(_adminRepo),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FeedCard(
              item: item,
              menu: UpdateMenu(item: item, onChanged: () => _changes++),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t, int id) async {
  await t.ensureVisible(find.byKey(Key('updateMenu_$id')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(Key('updateMenu_$id')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('no menu for strangers or when logged out', (t) async {
    await _pump(t, _cy, feedItem(authorId: 1));
    expect(find.byKey(const Key('updateMenu_7')), findsNothing);
    await _pump(t, null, feedItem(authorId: 1));
    expect(find.byKey(const Key('updateMenu_7')), findsNothing);
  });

  testWidgets('the author edits their update from the card', (t) async {
    await _pump(t, _ann, feedItem(authorId: 1));
    await _open(t, 7);
    expect(find.text('Edit update'), findsOneWidget);
    expect(find.byKey(const Key('updateMenuAdminEdit_7')), findsNothing);
    await t.tap(find.byKey(const Key('updateMenuEdit_7')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('updateBody')), 'better');
    await t.pump();
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    expect(_updates.edits.single.body, 'better');
    expect(_changes, 1);
  });

  testWidgets('the author deletes their update from the card', (t) async {
    await _pump(t, _ann, feedItem(authorId: 1));
    await _open(t, 7);
    await t.tap(find.byKey(const Key('updateMenuDelete_7')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('updateDeleteConfirm')));
    await t.pumpAndSettle();
    expect(_updates.deleted, [7]);
    expect(_changes, 1);
  });

  testWidgets('no author menu on a locked spot', (t) async {
    final item = feedItem(authorId: 1);
    await _pump(
      t,
      _ann,
      FeedItem(
        id: item.id,
        body: item.body,
        photos: item.photos,
        createdAt: item.createdAt,
        author: item.author,
        spot: const Spot(id: 5, title: 'L', lat: 1, lon: 2, locked: true),
      ),
    );
    expect(find.byKey(const Key('updateMenu_7')), findsNothing);
  });

  testWidgets('admins edit and hide anyone\'s update from the card', (t) async {
    await _pump(t, _admin, feedItem(authorId: 1));
    await _open(t, 7);
    expect(find.byKey(const Key('updateMenuEdit_7')), findsNothing);
    await t.tap(find.byKey(const Key('updateMenuAdminEdit_7')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('admin-update-body')), 'tidy');
    await t.tap(find.byKey(const Key('admin-update-save')));
    await t.pumpAndSettle();
    expect(_adminRepo.calls.last, 'update:7:{body: tidy}');

    await _open(t, 7);
    await t.tap(find.byKey(const Key('updateMenuAdminHide_7')));
    await t.pumpAndSettle();
    expect(_adminRepo.calls.last, 'update:7:{status: hidden}');
    expect(_changes, 2);
  });
}
