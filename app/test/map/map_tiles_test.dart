import 'package:app/features/map/map_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TileLayer> layerFor(
  WidgetTester t,
  Brightness b, {
  String key = '',
}) async {
  late TileLayer layer;
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: b),
      home: Builder(
        builder: (c) {
          layer = buildTileLayer(c, cartoKey: key);
          return const SizedBox();
        },
      ),
    ),
  );
  return layer;
}

void main() {
  testWidgets('dark theme with a key uses the keyed CARTO dark basemap', (
    t,
  ) async {
    final l = await layerFor(t, Brightness.dark, key: 'abc123');
    expect(
      l.urlTemplate,
      startsWith('https://basemaps.cartocdn.com/rastertiles/dark_all/'),
    );
    expect(l.urlTemplate, endsWith('?key=abc123'));
  });

  testWidgets(
    'dark theme without a key falls back to OpenStreetMap, never a watermarked tile',
    (t) async {
      final l = await layerFor(t, Brightness.dark);
      expect(l.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    },
  );

  testWidgets('light theme uses OpenStreetMap even with a key', (t) async {
    final l = await layerFor(t, Brightness.light, key: 'abc123');
    expect(l.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
  });
}
