import 'dart:async';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/users/author_link.dart';
import 'package:app/features/users/avatar_crop.dart';
import 'package:app/features/users/avatar_repository.dart';
import 'package:app/features/users/user_profile_screen.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'users_helpers.dart';

const _url = 'http://test/api/v1/media/avatars/1.jpg';

class _Avatars implements AvatarRepository {
  final calls = <String>[];
  Object? error;
  Completer<void>? gate;

  @override
  Future<String> upload(
    XFile file, {
    int? userId,
    void Function(double)? onProgress,
  }) async {
    calls.add(userId == null ? 'upload' : 'upload:$userId');
    onProgress?.call(0.5);
    await gate?.future;
    if (error != null) throw error!;
    return _url;
  }

  @override
  Future<void> remove({int? userId}) async {
    calls.add(userId == null ? 'remove' : 'remove:$userId');
    if (error != null) throw error!;
  }
}

UserProfile _profile(int id, {String? avatar, bool isMe = true}) => UserProfile(
  id: id,
  displayName: id == 1 ? 'Me' : 'Alice',
  createdAt: DateTime.utc(2025),
  isMe: isMe,
  avatarUrl: avatar,
);

Future<ProviderContainer> _pump(
  WidgetTester t,
  _Avatars avatars,
  FakeUsers users, {
  int userId = 1,
  User user = kMe,
  XFile? picked,
}) async {
  portrait(t);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        usersRepositoryProvider.overrideWithValue(users),
        authControllerProvider.overrideWith(() => FakeAuth(user)),
        avatarRepositoryProvider.overrideWithValue(avatars),
        avatarPickerProvider.overrideWithValue(() async => picked),
        // the cropper itself: avatar_crop_test.dart
        avatarCropperProvider.overrideWithValue((_, f) async => f),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: UserProfileScreen(userId: userId, asTab: true),
      ),
    ),
  );
  await t.pumpAndSettle();
  return ProviderScope.containerOf(t.element(find.byType(UserProfileScreen)));
}

Finder get _photo => find.descendant(
  of: find.byKey(const Key('ownAvatar')),
  matching: find.byType(CachedNetworkImage),
);

void main() {
  testWidgets('choosing a photo uploads it and shows it everywhere', (t) async {
    final avatars = _Avatars()..gate = Completer<void>();
    final users = FakeUsers(profiles: {1: _profile(1)});
    final picked = XFile.fromData(Uint8List(4), name: 'me.png');
    final c = await _pump(t, avatars, users, picked: picked);

    // your own picture has a camera badge; none yet, so the initial
    expect(find.byKey(const Key('avatarCameraBadge')), findsOneWidget);
    expect(_photo, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('ownAvatar')),
        matching: find.text('M'),
      ),
      findsOneWidget,
    );

    final loads = users.calls.where((x) => x == 'profile:1').length;
    await t.tap(find.byKey(const Key('ownAvatar')));
    await t.pumpAndSettle();
    expect(find.text('Choose photo'), findsOneWidget);
    // nothing to remove yet
    expect(find.byKey(const Key('avatarRemove')), findsNothing);
    await t.tap(find.byKey(const Key('avatarChoose')));
    await t.pump();
    await t.pump();

    // uploading: a spinner on the picture
    expect(find.byKey(const Key('avatarProgress')), findsOneWidget);
    expect(avatars.calls, ['upload']);
    avatars.gate!.complete();
    await t.pumpAndSettle();

    expect(find.byKey(const Key('avatarProgress')), findsNothing);
    expect(t.widget<CachedNetworkImage>(_photo).imageUrl, _url);
    expect(c.read(authControllerProvider).value?.avatarUrl, _url);
    expect(c.read(avatarOverridesProvider)[1], _url);
    // the profile is loaded again
    expect(users.calls.where((x) => x == 'profile:1').length, loads + 1);
  });

  testWidgets('removing the photo goes back to the initial', (t) async {
    final avatars = _Avatars();
    final users = FakeUsers(profiles: {1: _profile(1, avatar: _url)});
    final c = await _pump(
      t,
      avatars,
      users,
      user: const User(
        id: 1,
        email: 'me@x.de',
        displayName: 'Me',
        avatarUrl: _url,
      ),
    );
    expect(t.widget<CachedNetworkImage>(_photo).imageUrl, _url);

    await t.tap(find.byKey(const Key('ownAvatar')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('avatarRemove')));
    await t.pumpAndSettle();

    expect(avatars.calls, ['remove']);
    expect(_photo, findsNothing);
    expect(c.read(authControllerProvider).value?.avatarUrl, isNull);
  });

  testWidgets('a failed upload says why and keeps the old picture', (t) async {
    final avatars = _Avatars()
      ..error = ApiException(413, 'too_large', 'too large');
    final users = FakeUsers(profiles: {1: _profile(1)});
    final c = await _pump(
      t,
      avatars,
      users,
      picked: XFile.fromData(Uint8List(4), name: 'big.jpg'),
    );
    await t.tap(find.byKey(const Key('ownAvatar')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('avatarChoose')));
    await t.pumpAndSettle();
    expect(find.text('The photo is too large (maximum 8 MB).'), findsOneWidget);
    expect(_photo, findsNothing);
    expect(c.read(authControllerProvider).value?.avatarUrl, isNull);
  });

  testWidgets('a cancelled pick changes nothing', (t) async {
    final avatars = _Avatars();
    await _pump(t, avatars, FakeUsers(profiles: {1: _profile(1)}));
    await t.tap(find.byKey(const Key('ownAvatar')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('avatarChoose')));
    await t.pumpAndSettle();
    expect(avatars.calls, isEmpty);
  });

  testWidgets('someone else\'s profile shows their picture, not editable', (
    t,
  ) async {
    final avatars = _Avatars();
    await _pump(
      t,
      avatars,
      FakeUsers(profiles: {7: _profile(7, avatar: _url, isMe: false)}),
      userId: 7,
    );
    expect(find.byKey(const Key('ownAvatar')), findsNothing);
    expect(find.byKey(const Key('avatarCameraBadge')), findsNothing);
    final avatar = find.byKey(const Key('authorAvatar-7'));
    expect(
      t
          .widget<CachedNetworkImage>(
            find.descendant(
              of: avatar,
              matching: find.byType(CachedNetworkImage),
            ),
          )
          .imageUrl,
      _url,
    );
  });

  testWidgets('an admin changes someone else\'s picture, not their own', (
    t,
  ) async {
    final avatars = _Avatars();
    final c = await _pump(
      t,
      avatars,
      FakeUsers(profiles: {7: _profile(7, isMe: false)}),
      userId: 7,
      user: const User(
        id: 1,
        email: 'me@x.de',
        displayName: 'Me',
        isAdmin: true,
      ),
      picked: XFile.fromData(Uint8List(4), name: 'x.jpg'),
    );
    expect(find.byKey(const Key('avatarCameraBadge')), findsOneWidget);
    await t.tap(find.byKey(const Key('ownAvatar')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('avatarChoose')));
    await t.pumpAndSettle();
    expect(avatars.calls, ['upload:7']);
    expect(c.read(avatarOverridesProvider)[7], _url);
    // the admin's own picture stays as it was
    expect(c.read(authControllerProvider).value?.avatarUrl, isNull);
  });
}
