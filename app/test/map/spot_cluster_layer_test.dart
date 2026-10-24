import 'package:app/features/map/spot_cluster_layer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

List<Marker> markers() => [
  for (var i = 0; i < 6; i++)
    Marker(
      point: LatLng(48.10 + i * 0.01, 11.60 + i * 0.01),
      width: 30,
      height: 30,
      child: Container(key: ValueKey('m$i'), color: Colors.green),
    ),
];

Widget app(List<Marker> m, {Key? key}) => MaterialApp(
  home: SizedBox(
    width: 800,
    height: 600,
    child: FlutterMap(
      key: key,
      options: const MapOptions(
        initialCenter: LatLng(48.125, 11.625),
        initialZoom: 9,
      ),
      children: [SpotClusterLayer(markers: m)],
    ),
  ),
);

double zoom(WidgetTester t) =>
    MapCamera.of(t.element(find.byType(SpotClusterLayer))).zoom;

void main() {
  testWidgets('tapping a number bubble zooms in and the cluster splits', (
    tester,
  ) async {
    await tester.pumpWidget(app(markers()));
    await tester.pumpAndSettle();
    expect(find.text('6'), findsOneWidget);
    final before = zoom(tester);

    await tester.tap(find.text('6'));
    await tester.pumpAndSettle();

    expect(zoom(tester), greaterThan(before));
    expect(find.text('6'), findsNothing);
  });

  testWidgets(
    'a rebuild with an equal-but-new marker list mid-zoom still ends zoomed in',
    (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(app(markers(), key: key));
      await tester.pumpAndSettle();
      final before = zoom(tester);

      await tester.tap(find.text('6'));
      await tester.pump(const Duration(milliseconds: 100));
      // what the screen does when a fetch finishes during the animation
      await tester.pumpWidget(app(markers(), key: key));
      await tester.pumpAndSettle();

      expect(zoom(tester), greaterThan(before));
      expect(find.text('6'), findsNothing);
    },
  );

  testWidgets('tapping a number bubble does not flash the cluster outline', (
    tester,
  ) async {
    await tester.pumpWidget(app(markers()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6'));
    // sample the zoom animation several times; the outline polygon (the
    // green triangle) must never be on screen
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byType(PolygonLayer),
        findsNothing,
        reason: 'cluster outline visible at frame $i',
      );
    }
    await tester.pumpAndSettle();
  });
}
