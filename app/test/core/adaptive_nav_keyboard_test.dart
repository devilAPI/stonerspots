import 'package:app/core/adaptive_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page as the shell's tabs are: its own Scaffold, which makes room for
/// the keyboard.
class _Page extends StatelessWidget {
  const _Page();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: SizedBox.expand(key: Key('pageBody')));
}

void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1100, 700)]) {
    testWidgets('the keyboard is taken off a page once, at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: AdaptiveNavScaffold(
            items: const [
              NavItem(Icons.map_outlined, 'Map'),
              NavItem(Icons.dynamic_feed_outlined, 'Feed'),
              NavItem(Icons.person_outline, 'Profile'),
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            body: const _Page(),
          ),
        ),
      );
      expect(t.getSize(find.byKey(const Key('pageBody'))).height, size.height);

      // like iOS: the keyboard and its autofill bar cover the lower part
      final keyboard = size.height * 0.47;
      t.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await t.pumpAndSettle();
      // taken off twice, a phone's page was a 50 pt strip
      expect(
        t.getSize(find.byKey(const Key('pageBody'))).height,
        moreOrLessEquals(size.height - keyboard),
      );
      expect(t.takeException(), isNull);
    });
  }
}
