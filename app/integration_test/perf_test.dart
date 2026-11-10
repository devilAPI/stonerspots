// Frame timings while panning/zooming the map and scrolling the feed, on the
// real app against the running API. Profile mode gives meaningful numbers:
//   flutter drive -d linux --profile --driver=test_driver/perf_driver.dart \
//     --target=integration_test/perf_test.dart \
//     --dart-define-from-file=env/local.json
import 'package:app/main.dart';
import 'package:app/features/map/spot_cluster_layer.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';

/// A destination of the app's navigation: an icon in the rail; in the glass
/// tab bar, whose icons are drawn as text, its label.
Finder tab(IconData icon, List<String> labels) {
  final rail = find.byIcon(icon);
  if (rail.evaluate().isNotEmpty) return rail.first;
  return find
      .byWidgetPredicate((w) => w is Text && labels.contains(w.data))
      .first;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> idle(WidgetTester t, int ms) =>
      t.pump(Duration(milliseconds: ms)).then((_) async {
        await Future<void>.delayed(Duration(milliseconds: ms));
      });

  // TRACE=true: record a timeline with one event per widget build instead.
  const trace = bool.fromEnvironment('TRACE');

  Future<void> measure(Future<void> Function() action, String key) => trace
      ? binding.traceAction(action, reportKey: '$key-timeline')
      : binding.watchPerformance(action, reportKey: key);

  testWidgets('map and feed frame timings', (t) async {
    debugProfileBuildsEnabled = trace;
    debugProfileLayoutsEnabled = trace;
    await t.pumpWidget(const ProviderScope(child: StonerspotsApp()));
    await idle(t, 5000); // location timeout, first spots and tiles

    final map = find.byType(FlutterMap);
    final centre = t.getCenter(map);

    await measure(() async {
      for (var i = 0; i < 6; i++) {
        final d = i.isEven ? const Offset(300, 120) : const Offset(-300, -120);
        await t.timedDragFrom(centre, d, const Duration(milliseconds: 600));
        await idle(t, 300);
      }
      // scroll-wheel zoom in and out over the clusters
      for (final dy in const <double>[
        -120,
        -120,
        -120,
        -120,
        120,
        120,
        120,
        120,
      ]) {
        final p = TestPointer(1, PointerDeviceKind.mouse);
        await t.sendEventToBinding(p.hover(centre));
        await t.sendEventToBinding(p.scroll(Offset(0, dy)));
        await idle(t, 250);
      }
    }, 'map');

    await t.tap(tab(Icons.dynamic_feed_outlined, const ['Feed']));
    await idle(t, 4000);
    final list = find.byType(Scrollable).last;
    await measure(() async {
      for (var i = 0; i < 6; i++) {
        await t.fling(list, Offset(0, i < 4 ? -900 : 900), 2500);
        await idle(t, 700);
      }
    }, 'feed');

    // 3D: tilted, at street level over central Munich (buildings drawn)
    await t.tap(tab(Icons.map_outlined, const ['Map', 'Karte']));
    await idle(t, 1500);
    final controller = MapController.of(
      t.element(find.byType(SpotClusterLayer)),
    );
    controller.move(const LatLng(48.1372, 11.5755), 16.5);
    await idle(t, 1000);
    await t.tap(find.byKey(const Key('map3d')));
    await idle(t, 12000); // building tiles load and are read
    final centre3d = t.getCenter(find.byType(FlutterMap));
    await measure(() async {
      for (var i = 0; i < 8; i++) {
        final d = i.isEven ? const Offset(250, 120) : const Offset(-250, -120);
        await t.timedDragFrom(centre3d, d, const Duration(milliseconds: 700));
        await idle(t, 300);
      }
    }, 'map3d');
  });
}
