import 'package:app/features/map/map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TileLayer> layerFor(WidgetTester t, Brightness b) async {
  late TileLayer layer;
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: b),
      home: Builder(
        builder: (c) {
          layer = buildTileLayer(c);
          return const SizedBox();
        },
      ),
    ),
  );
  return layer;
}

void main() {
  testWidgets('dark theme uses the dark basemap', (t) async {
    final l = await layerFor(t, Brightness.dark);
    expect(l.urlTemplate, contains('dark_all'));
    expect(l.subdomains, contains('d'));
  });

  testWidgets('light theme uses the standard map', (t) async {
    final l = await layerFor(t, Brightness.light);
    expect(l.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  });
}
