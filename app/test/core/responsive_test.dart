import 'package:app/core/adaptive_nav.dart';
import 'package:app/core/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const phonePortrait = Size(400, 800);
const phoneLandscape = Size(844, 390);
const tabletPortrait = Size(768, 1024);
const desktop = Size(1400, 900);

Future<void> pumpAt(WidgetTester t, Size size, Widget child) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: child));
}

class Probe extends StatelessWidget {
  const Probe({super.key});
  @override
  Widget build(BuildContext context) =>
      Text('${context.useNavRail}/${context.extendedRail}/${context.twoPane}');
}

Widget nav(ValueChanged<int> onSelected, {int selected = 0}) =>
    AdaptiveNavScaffold(
      items: const [
        NavItem(Icons.map_outlined, 'Map'),
        NavItem(Icons.dynamic_feed_outlined, 'Feed'),
        NavItem(Icons.person_outline, 'Profile'),
      ],
      selectedIndex: selected,
      onSelected: onSelected,
      body: const Center(child: Text('body')),
    );

void main() {
  gutterTests();
  group('breakpoints', () {
    testWidgets('phone portrait: bottom bar, one pane', (t) async {
      await pumpAt(t, phonePortrait, const Probe());
      expect(find.text('false/false/false'), findsOneWidget);
    });
    testWidgets('phone landscape: rail and two panes, not extended', (t) async {
      await pumpAt(t, phoneLandscape, const Probe());
      expect(find.text('true/false/true'), findsOneWidget);
    });
    testWidgets('tablet portrait: rail and two panes', (t) async {
      await pumpAt(t, tabletPortrait, const Probe());
      expect(find.text('true/false/true'), findsOneWidget);
    });
    testWidgets('desktop: extended rail', (t) async {
      await pumpAt(t, desktop, const Probe());
      expect(find.text('true/true/true'), findsOneWidget);
    });
  });

  group('AdaptiveNavScaffold', () {
    testWidgets('phone portrait uses a bottom navigation bar', (t) async {
      await pumpAt(t, phonePortrait, nav((_) {}));
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('phone landscape uses a compact rail, no bottom bar', (
      t,
    ) async {
      await pumpAt(t, phoneLandscape, nav((_) {}));
      expect(find.byType(NavigationBar), findsNothing);
      final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('desktop uses an extended rail with labels', (t) async {
      await pumpAt(t, desktop, nav((_) {}));
      final rail = t.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(find.text('Feed'), findsOneWidget);
    });

    for (final size in [phonePortrait, phoneLandscape, desktop]) {
      testWidgets('selecting a destination reports its index at $size', (
        t,
      ) async {
        int? picked;
        await pumpAt(t, size, nav((i) => picked = i));
        await t.tap(find.byIcon(Icons.dynamic_feed_outlined));
        expect(picked, 1);
      });
    }

    testWidgets('no overflow on a very short landscape phone', (t) async {
      await pumpAt(t, const Size(640, 300), nav((_) {}));
      expect(t.takeException(), isNull);
    });
  });

  group('ContentWidth', () {
    testWidgets('caps the width on wide screens', (t) async {
      await pumpAt(
        t,
        desktop,
        const ContentWidth(
          child: SizedBox(key: Key('c'), width: double.infinity, height: 10),
        ),
      );
      expect(t.getSize(find.byKey(const Key('c'))).width, 680);
    });
    testWidgets('uses the full width on phones', (t) async {
      await pumpAt(
        t,
        phonePortrait,
        const ContentWidth(
          child: SizedBox(key: Key('c'), width: double.infinity, height: 10),
        ),
      );
      expect(t.getSize(find.byKey(const Key('c'))).width, 400);
    });
  });
}

void gutterTests() {
  test('sideGutter centres a capped column and is zero when narrow', () {
    expect(sideGutter(1400), (1400 - kContentMaxWidth) / 2);
    expect(sideGutter(400), 0);
    expect(sideGutter(kContentMaxWidth), 0);
  });
}
