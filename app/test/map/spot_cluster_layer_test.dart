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
  test('points within the radius group around the first one', () {
    final groups = clusterIndices(const [
      Offset(0, 0),
      Offset(100, 0), // far from 0
      Offset(30, 30), // near 0
      Offset(130, 10), // near 1
      Offset(500, 500),
    ], 60);
    expect(groups, [
      [0, 2],
      [1, 3],
      [4],
    ]);
  });

  test('neighbours across a grid cell edge still join', () {
    expect(clusterIndices(const [Offset(59, 59), Offset(61, 61)], 60), [
      [0, 1],
    ]);
  });

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
}
