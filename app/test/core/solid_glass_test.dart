import 'package:app/core/settings.dart';
import 'package:app/features/zones/zone_consent.dart';

import 'dart:ui' as ui;

import 'package:app/core/adaptive_nav.dart';
import 'package:app/core/glass.dart';
import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/core/theme.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/feed/feed_screen.dart';
import 'package:app/features/map/map_screen.dart';
import 'package:app/features/map/spot_pull_sheet.dart';
import 'package:app/features/map/spots_controller.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const phone = Size(400, 800);
const desktop = Size(1400, 900);
const tabs = [
  BottomBarTab(icon: Icons.map_outlined, label: 'Map'),
  BottomBarTab(icon: Icons.dynamic_feed_outlined, label: 'Feed'),
  BottomBarTab(icon: Icons.person_outline, label: 'Profile'),
];
const navItems = [
  NavItem(Icons.map_outlined, 'Map'),
  NavItem(Icons.dynamic_feed_outlined, 'Feed'),
  NavItem(Icons.person_outline, 'Profile'),
];

class _Spots implements SpotsRepository {
  @override
  Future<List<Spot>> inBounds(
    LatLngBounds bounds, {
    List<SpotTag> tags = const [],
  }) async => const [];
}

class _Location implements LocationService {
  @override
  Future<LatLng?> currentPosition() async => const LatLng(48.1, 11.6);
}

class _Feed implements FeedRepository {
  @override
  Future<FeedPage> fetch({
    required FeedSort sort,
    double? lat,
    double? lon,
    String? cursor,
    int limit = 20,
    List<SpotTag> tags = const [],
    bool following = false,
  }) async => const FeedPage([], null);
}

Future<void> pumpIn(
  WidgetTester t,
  Widget home, {
  required bool solid,
  Size size = phone,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    SolidGlass(
      enabled: solid,
      child: ProviderScope(
        overrides: [
          // zones (and their first-use disclaimer) are tested in test/zones
          zonesEnabledProvider.overrideWith(() => BoolSetting('zones_enabled')),
          mapSpotsRepositoryProvider.overrideWithValue(_Spots()),
          locationServiceProvider.overrideWithValue(_Location()),
          mapDebounceProvider.overrideWithValue(Duration.zero),
          feedRepositoryProvider.overrideWithValue(_Feed()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(padding: padding),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  await t.pump();
}

/// Nothing of the glass engine in the tree: no backdrop read at all.
void expectNoGlass() {
  expect(find.byType(LiquidGlass), findsNothing);
  expect(find.byType(LiquidGlassLayer), findsNothing);
  expect(find.byType(LoupeTabBar), findsNothing);
  expect(find.byType(LiquidStretch), findsNothing);
  expect(find.byType(BackdropFilter), findsNothing);
}

/// A pixel of what [boundary] painted.
Future<ui.Color> pixelAt(WidgetTester t, Key boundary, Offset at) async {
  final render = t.renderObject<RenderRepaintBoundary>(find.byKey(boundary));
  final bytes = await t.runAsync(() async {
    final image = await render.toImage();
    return image.toByteData();
  });
  final i = (at.dy.toInt() * render.size.width.toInt() + at.dx.toInt()) * 4;
  return ui.Color.fromARGB(
    bytes!.getUint8(i + 3),
    bytes.getUint8(i),
    bytes.getUint8(i + 1),
    bytes.getUint8(i + 2),
  );
}

void main() {
  group('GlassSurface', () {
    testWidgets('is a lens by default', (t) async {
      await pumpIn(t, const GlassSurface(child: Text('hi')), solid: false);
      expect(find.byType(LiquidGlass), findsOneWidget);
    });

    testWidgets('solid: no lens, and nothing shines through', (t) async {
      const red = ui.Color(0xFFFF0000);
      await pumpIn(
        t,
        const RepaintBoundary(
          key: Key('shot'),
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: red)),
              Positioned(
                left: 20,
                top: 20,
                width: 200,
                height: 100,
                child: GlassSurface(child: SizedBox.expand()),
              ),
            ],
          ),
        ),
        solid: true,
      );
      expectNoGlass();
      expect(
        await pixelAt(t, const Key('shot'), const Offset(120, 70)),
        kSolidGlass,
      );
      // still a rounded surface: its corner shows the page
      expect(await pixelAt(t, const Key('shot'), const Offset(21, 21)), red);
    });

    testWidgets('solid: text keeps the on-glass colour', (t) async {
      await pumpIn(
        t,
        GlassSurface(
          child: Builder(
            builder: (context) =>
                Text('${DefaultTextStyle.of(context).style.color?.toARGB32()}'),
          ),
        ),
        solid: true,
      );
      expect(find.text('${kOnGlass.toARGB32()}'), findsOneWidget);
    });

    testWidgets('solid: the shared tint is opaque', (t) async {
      late Color tint;
      await pumpIn(
        t,
        Builder(
          builder: (context) {
            tint = glassTint(context);
            return const SizedBox();
          },
        ),
        solid: true,
      );
      expect(tint.a, 1);
    });

    for (final solid in [false, true]) {
      testWidgets('empty areas: clear glass lets taps through, solid does not '
          '(solid: $solid)', (t) async {
        var behind = 0;
        var inside = 0;
        await pumpIn(
          t,
          Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => behind++,
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  width: 300,
                  height: 100,
                  child: GlassSurface(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        key: const Key('inside'),
                        icon: const Icon(Icons.add),
                        onPressed: () => inside++,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          solid: solid,
        );
        await t.tapAt(const Offset(100, 50));
        await t.pump(const Duration(milliseconds: 400));
        final expected = solid ? 0 : 1;
        expect(behind, expected);
        await t.tap(find.byKey(const Key('inside')));
        await t.pump(const Duration(milliseconds: 400));
        expect(inside, 1);
        expect(behind, expected);
      });
    }
  });

  group('same layout with and without glass', () {
    /// Lays [home] out both ways: [finders] must not move.
    Future<void> expectSameRects(
      WidgetTester t,
      Widget home,
      List<Finder> finders, {
      Size size = phone,
      EdgeInsets padding = EdgeInsets.zero,
      Future<void> Function()? open,
    }) async {
      Future<List<Rect>> measure(bool solid) async {
        // a blank tree first: a sheet from the other mode would stay open
        await t.pumpWidget(const SizedBox());
        await pumpIn(t, home, solid: solid, size: size, padding: padding);
        await open?.call();
        if (solid) expectNoGlass();
        return [for (final f in finders) t.getRect(f)];
      }

      final glass = await measure(false);
      final solid = await measure(true);
      expect(solid, glass);
    }

    testWidgets('app bar', (t) async {
      await expectSameRects(
        t,
        Scaffold(
          appBar: GlassAppBar(
            title: const Text('Title'),
            actions: [
              IconButton(
                key: const Key('action'),
                icon: const Icon(Icons.settings),
                onPressed: () {},
              ),
            ],
          ),
        ),
        [find.text('Title'), find.byKey(const Key('action'))],
      );
    });

    testWidgets('floating button', (t) async {
      await expectSameRects(
        t,
        Scaffold(
          body: Stack(
            children: [
              Positioned(
                right: 16,
                bottom: 16,
                child: GlassFab(
                  key: const Key('fab'),
                  radius: 24,
                  icon: Icons.add,
                  label: const Text('Add spot'),
                  onPressed: () {},
                ),
              ),
            ],
          ),
        ),
        [
          find.byKey(const Key('fab')),
          find.byIcon(Icons.add),
          find.text('Add spot'),
        ],
      );
    });

    testWidgets('tab bar, above the safe area', (t) async {
      await expectSameRects(
        t,
        AdaptiveNavScaffold(
          items: navItems,
          selectedIndex: 1,
          onSelected: (_) {},
          body: const Center(child: Text('body')),
        ),
        [
          // glass tabs draw their icons as text, and every tab twice
          find.text('Map').first,
          find.text('Feed').first,
          find.text('Profile').first,
          find.text('body'),
        ],
        padding: const EdgeInsets.only(bottom: 30),
      );
    });

    testWidgets('rail', (t) async {
      await expectSameRects(
        t,
        AdaptiveNavScaffold(
          items: navItems,
          selectedIndex: 1,
          onSelected: (_) {},
          body: const Center(child: Text('body')),
        ),
        [find.byType(NavigationRail), find.text('Feed'), find.text('body')],
        size: desktop,
      );
    });

    testWidgets('sheet on a wide window', (t) async {
      await expectSameRects(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => showGlassSheet<void>(
                context: context,
                radius: 32,
                useRootNavigator: true,
                isScrollControlled: true,
                constraints: const BoxConstraints(maxWidth: 560),
                builder: (_) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('in the sheet'),
                ),
              ),
            ),
          ),
        ),
        [find.text('in the sheet')],
        size: desktop,
        padding: const EdgeInsets.only(bottom: 20),
        open: () async {
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
        },
      );
    });
  });

  group('whole pages without glass', () {
    testWidgets('the map and its chrome', (t) async {
      await pumpIn(t, const MapScreen(), solid: true);
      await t.pumpAndSettle();
      expectNoGlass();
      expect(find.byKey(const Key('addSpot')), findsOneWidget);
      expect(find.byKey(const Key('mapLocateMe')), findsOneWidget);
      await t.tap(find.byKey(const Key('mapLayer')));
      await t.pumpAndSettle();
      expect(find.byTooltip('Satellite'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the feed header', (t) async {
      await pumpIn(t, const FeedScreen(), solid: true);
      await t.pumpAndSettle();
      expectNoGlass();
      expect(find.byKey(const Key('feedTagRow')), findsOneWidget);
    });
  });

  group('GlassTabBar without glass', () {
    Future<List<int>> pumpBar(WidgetTester t) async {
      final picked = <int>[];
      await pumpIn(
        t,
        StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Stack(
              children: [
                GlassTabBar(
                  width: 360,
                  items: tabs,
                  selectedIndex: picked.isEmpty ? 0 : picked.last,
                  onChanged: (i) => setState(() => picked.add(i)),
                ),
              ],
            ),
          ),
        ),
        solid: true,
      );
      return picked;
    }

    Color labelColor(WidgetTester t, String label) =>
        t.widget<Text>(find.text(label)).style!.color!;

    testWidgets('a tap selects the tab', (t) async {
      final picked = await pumpBar(t);
      expectNoGlass();
      expect(labelColor(t, 'Map'), kOnGlass);
      await t.tap(find.text('Feed'));
      await t.pumpAndSettle();
      expect(picked, [1]);
      expect(labelColor(t, 'Feed'), kOnGlass);
      expect(labelColor(t, 'Map'), isNot(kOnGlass));
    });

    testWidgets('the selection pill slides to the tab', (t) async {
      await pumpBar(t);
      final pill = find.byKey(const Key('solidTabPill'));
      final before = t.getCenter(pill).dx;
      await t.tap(find.text('Profile'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final moving = t.getCenter(pill).dx;
      await t.pumpAndSettle();
      final after = t.getCenter(pill).dx;
      expect(moving, inExclusiveRange(before, after));
      expect(after, closeTo(t.getCenter(find.text('Profile')).dx, 1));
    });

    testWidgets('press and hold drags the selection to another tab', (t) async {
      final picked = await pumpBar(t);
      final g = await t.startGesture(t.getCenter(find.text('Map')));
      await t.pump(const Duration(milliseconds: 150));
      await g.moveTo(t.getCenter(find.text('Profile')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(
        t.getCenter(find.byKey(const Key('solidTabPill'))).dx,
        closeTo(t.getCenter(find.text('Profile')).dx, 1),
      );
      expect(picked, isEmpty);
      await g.up();
      await t.pumpAndSettle();
      expect(picked, [2]);
    });

    testWidgets('tabs stay usable with a screen reader', (t) async {
      final semantics = t.ensureSemantics();
      final picked = await pumpBar(t);
      expect(
        t.getSemantics(find.text('Map')),
        matchesSemantics(
          label: 'Map',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
          hasFocusAction: false,
        ),
      );
      t.semantics.tap(find.semantics.byLabel('Feed'));
      await t.pump();
      expect(picked, [1]);
      semantics.dispose();
    });
  });

  group('navigation', () {
    AdaptiveNavScaffold nav(ValueChanged<int> onSelected) =>
        AdaptiveNavScaffold(
          items: navItems,
          selectedIndex: 0,
          onSelected: onSelected,
          body: const Center(child: Text('body')),
        );

    testWidgets('phone: the tabs work without glass', (t) async {
      int? picked;
      await pumpIn(t, nav((i) => picked = i), solid: true);
      expectNoGlass();
      await t.tap(find.text('Profile'));
      await t.pumpAndSettle();
      expect(picked, 2);
    });

    testWidgets('the rail works without glass', (t) async {
      int? picked;
      await pumpIn(t, nav((i) => picked = i), solid: true, size: desktop);
      expectNoGlass();
      await t.tap(find.text('Feed'));
      await t.pumpAndSettle();
      expect(picked, 1);
    });

    testWidgets('switching glass off keeps the page under the bar', (t) async {
      final key = GlobalKey<_PageState>();
      Widget app(bool solid) => SolidGlass(
        enabled: solid,
        child: MaterialApp(
          home: AdaptiveNavScaffold(
            items: navItems,
            selectedIndex: 0,
            onSelected: (_) {},
            body: _Page(key: key),
          ),
        ),
      );
      t.view.physicalSize = phone;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(app(false));
      final state = key.currentState;
      expect(find.byType(LoupeTabBar), findsOneWidget);
      await t.pumpWidget(app(true));
      await t.pump();
      expectNoGlass();
      expect(key.currentState, same(state));
    });
  });

  testWidgets('the floating button reacts to taps without glass', (t) async {
    var pressed = 0;
    await pumpIn(
      t,
      Scaffold(
        body: Center(
          child: GlassFab(
            key: const Key('fab'),
            radius: 24,
            icon: Icons.add,
            label: const Text('Add spot'),
            onPressed: () => pressed++,
          ),
        ),
      ),
      solid: true,
    );
    expectNoGlass();
    await t.tap(find.byKey(const Key('fab')));
    await t.pump(const Duration(milliseconds: 400));
    expect(pressed, 1);
  });

  group('sheets without glass', () {
    testWidgets('the wide-window sheet opens and closes as before', (t) async {
      await pumpIn(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => showGlassSheet<void>(
                context: context,
                radius: 32,
                builder: (_) => const SizedBox(height: 200),
              ),
            ),
          ),
        ),
        solid: true,
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expectNoGlass();
      expect(find.byType(BottomSheet), findsOneWidget);
      await t.tapAt(const Offset(200, 100)); // on the barrier
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    Future<List<int>> openPullSheet(WidgetTester t) async {
      final expanded = <int>[];
      await pumpIn(
        t,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('open'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                enableDrag: false,
                builder: (_) => SpotPullSheet(
                  spot: const Spot(
                    id: 1,
                    title: 'Lake bench',
                    lat: 48.1,
                    lon: 11.6,
                  ),
                  page: const GlassAppBar(title: Text('the page')),
                  onOpen: () {},
                  onExpanded: () {
                    expanded.add(1);
                    Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        transitionDuration: Duration.zero,
                        pageBuilder: (_, _, _) => const Text('real page'),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        solid: true,
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return expanded;
    }

    testWidgets('the card pulls up into the page without any lens', (t) async {
      final expanded = await openPullSheet(t);
      expectNoGlass();
      final g = await t.startGesture(t.getCenter(find.text('Lake bench')));
      // none at any point of the pull, while the page comes in behind
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(0, -80));
        await t.pump();
        expectNoGlass();
      }
      expect(find.text('the page'), findsOneWidget);
      await g.moveBy(const Offset(0, -700));
      await t.pump();
      await g.up();
      await t.pumpAndSettle();
      expect(expanded, [1]);
      expect(find.text('real page'), findsOneWidget);
      expect(find.text('Lake bench'), findsNothing);
      expectNoGlass();
      expect(t.takeException(), isNull);
    });

    testWidgets('a short pull springs back, a pull down closes', (t) async {
      final expanded = await openPullSheet(t);
      final rest = t.getTopLeft(find.text('Lake bench'));
      await t.drag(find.text('Lake bench'), const Offset(0, -40));
      await t.pumpAndSettle();
      expect(expanded, isEmpty);
      expect(t.getTopLeft(find.text('Lake bench')), rest);
      await t.drag(find.text('Lake bench'), const Offset(0, 300));
      await t.pumpAndSettle();
      expect(find.text('Lake bench'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}

class _Page extends StatefulWidget {
  const _Page({super.key});

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
