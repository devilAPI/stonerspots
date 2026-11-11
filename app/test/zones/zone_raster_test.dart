import 'dart:ui' as ui;

import 'package:app/features/zones/zone_models.dart';
import 'package:app/features/zones/zone_paint.dart';
import 'package:app/features/zones/zone_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'zone_fixtures.dart';

const _size = Size(400, 800);

MapCamera _camera(LatLng center, double zoom) => MapCamera(
  crs: const Epsg3857(),
  center: center,
  zoom: zoom,
  rotation: 0,
  nonRotatedSize: _size,
);

void main() {
  final tile = ZoneTileId.at(base.latitude, base.longitude);
  final graphics = [
    ZoneTileGraphics.build(tile, [
      square('w/1', ZoneKind.school, size: 60),
      point('n/2', ZoneKind.playground, at(150, 0)),
    ]),
  ];

  void paint(ZoneRaster r, MapCamera c, {List<ZoneTileGraphics>? tiles}) {
    final recorder = ui.PictureRecorder();
    ZonePainter(
      camera: c,
      tiles: tiles ?? graphics,
      banNow: false,
      raster: r,
      pixelRatio: 3,
    ).paint(Canvas(recorder), _size);
    recorder.endRecording().dispose();
  }

  test('the zones are drawn once and then only moved and scaled', () {
    final r = ZoneRaster();
    addTearDown(r.dispose);
    paint(r, _camera(base, 16));
    expect(r.draws, 1);
    // panning within the margin, zooming a little: the same image
    paint(r, _camera(at(60, -40), 16));
    paint(r, _camera(at(-80, 90), 16.3));
    paint(r, _camera(base, 15.6));
    expect(r.draws, 1);
  });

  test('drawn again when the map leaves it, zooms far or tiles change', () {
    final r = ZoneRaster();
    addTearDown(r.dispose);
    paint(r, _camera(base, 16));
    // a whole screen to the east at zoom 16 (about 960 m)
    paint(r, _camera(at(1000, 0), 16));
    expect(r.draws, 2);
    paint(r, _camera(at(1000, 0), 17));
    expect(r.draws, 3);
    paint(r, _camera(at(1000, 0), 17), tiles: [...graphics]);
    expect(r.draws, 3, reason: 'the same tiles in a new list');
    paint(
      r,
      _camera(at(1000, 0), 17),
      tiles: [ZoneTileGraphics.build(tile, const [])],
    );
    expect(r.draws, 4);
  });

  test('a large window is drawn coarser, within the pixel budget', () {
    final r = ZoneRaster(pixelBudget: 1000000);
    addTearDown(r.dispose);
    paint(r, _camera(base, 16));
    expect(r.draws, 1);
    expect(r.imagePixels, lessThanOrEqualTo(1000000 * 1.01));
  });
}
