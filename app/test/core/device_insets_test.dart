import 'package:app/core/device_insets.dart';
import 'package:app/core/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // An iPhone home-screen web app: Flutter's web engine reports no safe
  // area, the browser does (status bar 47, home indicator 34).
  const iphone = EdgeInsets.only(top: 47, bottom: 34);

  Future<void> pump(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        builder: (_, child) =>
            DeviceInsets(debugInsets: iphone, child: child!),
        home: page,
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('the tab bar stays above the home indicator', (t) async {
    await pump(
      t,
      Scaffold(
        body: Stack(
          children: [
            GlassTabBar(
              width: 300,
              items: const [
                BottomBarTab(icon: Icons.map_outlined, label: 'Map'),
                BottomBarTab(icon: Icons.person_outline, label: 'Profile'),
              ],
              selectedIndex: 0,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    final bar = t.getRect(find.byType(LoupeTabBar));
    expect(bar.bottom, 844 - 34 - kGlassTabBarGap);
  });

  testWidgets('pages start below the status bar, also inside a Scaffold', (
    t,
  ) async {
    late double top;
    await pump(
      t,
      Scaffold(
        body: Builder(
          builder: (context) {
            top = GlassAppBar.contentTop(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(top, greaterThanOrEqualTo(47 + kGlassAppBarHeight));
  });
}
