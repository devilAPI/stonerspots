import 'package:app/core/user_avatar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester t, Widget child) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('without a picture: the initial on the user\'s colour', (
    t,
  ) async {
    await _pump(t, const UserAvatar(userId: 7, name: 'alice', radius: 20));
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(t.getSize(find.byType(UserAvatar)), const Size(40, 40));
    final box = t.widget<ColoredBox>(
      find.byKey(const Key('userAvatarInitial')),
    );
    expect(box.color, avatarColor(7));
  });

  testWidgets('with a picture: the photo, decoded at the circle\'s size', (
    t,
  ) async {
    await _pump(
      t,
      const UserAvatar(
        userId: 7,
        name: 'Alice',
        url: 'http://test/a.jpg',
        radius: 16,
      ),
    );
    final image = t.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(image.imageUrl, 'http://test/a.jpg');
    // 32 logical px at the test's device pixel ratio
    final dpr = t.view.devicePixelRatio;
    expect(image.memCacheWidth, (32 * dpr).round());
    expect(t.getSize(find.byType(UserAvatar)), const Size(32, 32));
  });

  test('colours tell users apart; initials cope with empty names', () {
    expect(avatarColor(1), isNot(avatarColor(2)));
    expect(avatarColor(5), avatarColor(5));
    expect(avatarInitial(''), '?');
    expect(avatarInitial('  '), '?');
    expect(avatarInitial('émile'), 'É');
  });

  testWidgets('a tap target only with onTap', (t) async {
    var taps = 0;
    await _pump(t, UserAvatar(userId: 1, name: 'Bo', onTap: () => taps++));
    await t.tap(find.byType(UserAvatar));
    expect(taps, 1);

    await _pump(t, const UserAvatar(userId: 1, name: 'Bo'));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a deleted account is a grey placeholder', (t) async {
    await _pump(t, const DeletedAvatar(radius: 10));
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });
}
