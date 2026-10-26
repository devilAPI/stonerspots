import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_edit_dialogs.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/admin/admin_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../spots/update_helpers.dart';

/// Records the update and photo calls of the admin update dialog.
class _Fake implements AdminRepository {
  final calls = <String>[];
  Object? deleteError;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> updateUpdate(int id, AdminUpdatePatch patch) async =>
      calls.add('update:$id:${patch.toJson()}');

  @override
  Future<void> rotatePhoto(int id, int degrees) async =>
      calls.add('rotate:$id:$degrees');

  @override
  Future<void> deletePhoto(int id) async {
    calls.add('delete:$id');
    if (deleteError != null) throw deleteError!;
  }
}

const _photos = [
  PhotoRef(id: 1, url: 'http://x/1.jpg', thumbUrl: 'http://x/1_t.jpg'),
  PhotoRef(id: 2, url: 'http://x/2.jpg', thumbUrl: 'http://x/2_t.jpg'),
];

/// Opens the dialog; the returned getter reads what it resolved to.
Future<bool? Function()> _open(
  WidgetTester t,
  _Fake repo,
  FeedItem item,
) async {
  bool? result;
  await t.pumpWidget(
    ProviderScope(
      overrides: [adminRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  result = await showAdminUpdateDialog(c, item),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return () => result;
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('rotations add up and removals apply on save', (t) async {
    final repo = _Fake();
    final result = await _open(t, repo, feedItem(photos: _photos));

    await _tap(t, 'admin-photo-1-right');
    await _tap(t, 'admin-photo-1-right');
    await _tap(t, 'admin-photo-1-left');
    final box = t.widget<RotatedBox>(
      find.descendant(
        of: find.byKey(const Key('admin-photo-1')),
        matching: find.byType(RotatedBox),
      ),
    );
    expect(box.quarterTurns, 1); // previewed before saving
    await _tap(t, 'admin-photo-2-remove');
    // rotations of a photo that is removed are never sent
    await _tap(t, 'admin-photo-2-remove');
    await _tap(t, 'admin-photo-2-right');
    await _tap(t, 'admin-photo-2-remove');
    expect(repo.calls, isEmpty);

    await _tap(t, 'admin-update-save');
    expect(repo.calls, ['rotate:1:90', 'delete:2']);
    expect(result(), isTrue);
  });

  testWidgets('cancel sends nothing', (t) async {
    final repo = _Fake();
    final result = await _open(t, repo, feedItem(photos: _photos));
    await _tap(t, 'admin-photo-1-right');
    await _tap(t, 'admin-photo-2-remove');
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(result(), isFalse);
  });

  testWidgets('an update without text keeps at least one photo', (t) async {
    final repo = _Fake();
    await _open(t, repo, feedItem(body: '', photos: _photos));
    await _tap(t, 'admin-photo-1-remove');
    await _tap(t, 'admin-photo-2-remove');
    await _tap(t, 'admin-update-save');
    expect(repo.calls, isEmpty);
    expect(find.byKey(const Key('admin-update-error')), findsOneWidget);
  });

  testWidgets('a retry after a failed step does not repeat done steps', (
    t,
  ) async {
    final repo = _Fake()
      ..deleteError = ApiException(409, 'last_photo', 'no text');
    final result = await _open(t, repo, feedItem(photos: _photos));
    await t.enterText(find.byKey(const Key('admin-update-body')), 'new');
    await _tap(t, 'admin-photo-1-right');
    await _tap(t, 'admin-photo-2-remove');
    await _tap(t, 'admin-update-save');
    expect(repo.calls, ['update:7:{body: new}', 'rotate:1:90', 'delete:2']);
    expect(find.byKey(const Key('admin-update-error')), findsOneWidget);

    repo
      ..calls.clear()
      ..deleteError = null;
    await _tap(t, 'admin-update-save');
    expect(repo.calls, ['delete:2']);
    expect(result(), isTrue);
  });
}
