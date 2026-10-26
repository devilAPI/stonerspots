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

  // CARTO answers 403 (blank tile) above zoom 18, OSM stops at 19; closer
  // views must scale those tiles up instead of asking for tiles that do not exist.
  testWidgets('dark tiles are never requested above zoom 18', (t) async {
    final l = await layerFor(t, Brightness.dark, key: 'abc123');
    expect(l.maxNativeZoom, 18);
  });

  testWidgets('osm tiles are never requested above zoom 19', (t) async {
    final l = await layerFor(t, Brightness.light);
    expect(l.maxNativeZoom, 19);
  });

  test('the maps cannot be zoomed further than scaled tiles stay readable', () {
    expect(kMapMaxZoom, lessThanOrEqualTo(20));
    expect(kMapMaxZoom, greaterThanOrEqualTo(19));
  });

  testWidgets('the transport map follows the theme and carries the key', (
    t,
  ) async {
    for (final (b, style) in [
      (Brightness.dark, 'transport-dark'),
      (Brightness.light, 'transport'),
    ]) {
      late TileLayer l;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: b),
          home: Builder(
            builder: (c) {
              l = buildTransitTileLayer(c, key: 'tf1');
              return const SizedBox();
            },
          ),
        ),
      );
      await t.pumpAndSettle(); // the theme change animates
      expect(
        l.urlTemplate,
        'https://tile.thunderforest.com/$style/{z}/{x}/{y}{r}.png?apikey=tf1',
      );
    }
    expect(hasTransitMap(key: ''), isFalse);
    expect(hasTransitMap(key: 'tf1'), isTrue);
  });
}
