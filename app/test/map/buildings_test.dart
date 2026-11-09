import 'dart:typed_data';
import 'dart:io';
import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:app/features/map/buildings/building_layer.dart';
import 'package:app/features/map/buildings/buildings.dart';
import 'package:app/features/map/buildings/map_tilt.dart';
import 'package:app/features/map/buildings/mvt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // OpenFreeMap tile 14/8718/5685: central Munich around Marienplatz
  final bytes = File('test/map/fixtures/munich_14_8718_5685.pbf')
      .readAsBytesSync();

  test('reads the building layer of a real tile', () {
    final layer = readMvtLayer(bytes, 'building')!;
    expect(layer.extent, 4096);
    expect(layer.features.length, greaterThan(100));
    final heights = layer.features
        .map((f) => f.properties['render_height'])
        .whereType<num>();
    expect(heights, isNotEmpty);
    expect(readMvtLayer(bytes, 'no_such_layer'), isNull);
  });

  test('buildings: inside the tile, with heights', () {
    final list = parseBuildingTile(bytes, 8718, 5685);
    expect(list.length, greaterThan(1000)); // one per footprint
    final n = math.pow(2, 14);
    for (final b in list) {
      expect(b.height, greaterThan(b.minHeight));
      final cx = b.centerX * n, cy = b.centerY * n;
      expect(cx, inInclusiveRange(8718, 8719));
      expect(cy, inInclusiveRange(5685, 5686));
    }
    // every roof is triangulated, with valid point indices
    for (final b in list) {
      expect(b.roof.length % 3, 0);
      expect(b.roof, isNotEmpty);
      final points = b.points.length ~/ 2;
      expect(b.roof.every((i) => i >= 0 && i < points), isTrue);
      expect(b.ringEnds.last, points);
    }
    // the Frauenkirche towers (99 m) are in this tile
    final tallest = list.map((b) => b.height).reduce(math.max);
    expect(tallest, greaterThan(80));
  });

  test('the Neues Rathaus at Marienplatz is there and tall', () {
    // Neues Rathaus: 48.1375, 11.5757 (tower 85 m)
    double mx(double lon) => (lon + 180) / 360;
    double my(double lat) {
      final s = math.sin(lat * math.pi / 180);
      return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    }

    final x = mx(11.5757), y = my(48.1375);
    final list = parseBuildingTile(bytes, 8718, 5685);
    // its parts are separate footprints now: the tower is among those
    // within about 60 m
    const near = 0.0000005;
    final here = list.where(
      (b) => (b.centerX - x).abs() < near && (b.centerY - y).abs() < near,
    );
    expect(here.length, greaterThan(1));
    expect(here.map((b) => b.height).reduce(math.max), greaterThan(60));
  });

  test('the painter draws the buildings of Marienplatz in 3D', () {
    const screen = Size(900, 500);
    final tilt = MapTilt(screen: screen, pitchDegrees: kMapPitch);
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: const LatLng(48.1372, 11.5755),
      zoom: 17,
      rotation: 20,
      nonRotatedSize: tilt.mapSize,
    );
    final painter = BuildingPainter(
      camera: camera,
      tilt: tilt,
      buildings: parseBuildingTile(bytes, 8718, 5685),
      palette: BuildingPalette.dark,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), tilt.mapSize);
    recorder.endRecording().dispose();
    // walls and roofs of many buildings
    expect(painter.lastTriangles, greaterThan(1000));

    // nothing in view: nothing drawn, no error
    final empty = BuildingPainter(
      camera: camera,
      tilt: tilt,
      buildings: const [],
      palette: BuildingPalette.light,
    );
    final r2 = ui.PictureRecorder();
    empty.paint(Canvas(r2), tilt.mapSize);
    r2.endRecording().dispose();
    expect(empty.lastTriangles, 0);
  });

  test('only the walls facing the viewer are drawn', () {
    const screen = Size(900, 500);
    final tilt = MapTilt(screen: screen, pitchDegrees: kMapPitch);
    const centre = LatLng(48.1372, 11.5755);
    double mx(double lon) => (lon + 180) / 360;
    double my(double lat) {
      final s = math.sin(lat * math.pi / 180);
      return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    }

    // a 40 m square house right in the middle, ring as in MVT (y down,
    // positive area: north-west, north-east, south-east, south-west)
    final x = mx(centre.longitude), y = my(centre.latitude);
    const d = 0.00000015; // ~20 m in world units at this latitude
    final house = Building(
      points: Float64List.fromList([
        x - d, y - d, x + d, y - d, x + d, y + d, x - d, y + d, //
      ]),
      ringEnds: Int32List.fromList([4]),
      roof: Int32List.fromList([0, 1, 2, 0, 2, 3]),
      height: 30,
      minHeight: 0,
    );
    final camera = MapCamera(
      crs: const Epsg3857(),
      center: centre,
      zoom: 18,
      rotation: 0,
      nonRotatedSize: tilt.mapSize,
    );
    final p = BuildingPainter(
      camera: camera,
      tilt: tilt,
      buildings: [house],
      palette: BuildingPalette.light,
    );
    final rec = ui.PictureRecorder();
    p.paint(Canvas(rec), tilt.mapSize);
    rec.endRecording().dispose();
    expect(p.lastBuildings, 1);
    // looking north from the middle: the south wall only (its foot is
    // nearer, i.e. lower on the map than the house's middle); the side
    // walls are edge-on, the north wall is behind the house
    final middle = camera.latLngToScreenOffset(centre).dy;
    expect(p.debugWallFeet, hasLength(1));
    expect(p.debugWallFeet.single, greaterThan(middle));
  });

  test('a building reaching the eye is left out, not drawn torn apart', () {
    const screen = Size(900, 500);
    final tilt = MapTilt(screen: screen, pitchDegrees: kMapPitch);
    const centre = LatLng(48.1372, 11.5755);
    double mx(double lon) => (lon + 180) / 360;
    double my(double lat) {
      final s = math.sin(lat * math.pi / 180);
      return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
    }

    Building house(double height) {
      final x = mx(centre.longitude), y = my(centre.latitude);
      const d = 0.00000015;
      return Building(
        points: Float64List.fromList([
          x - d, y - d, x + d, y - d, x + d, y + d, x - d, y + d, //
        ]),
        ringEnds: Int32List.fromList([4]),
        roof: Int32List.fromList([0, 1, 2, 0, 2, 3]),
        height: height,
        minHeight: 0,
      );
    }

    int drawn(double zoom, double height) {
      final p = BuildingPainter(
        camera: MapCamera(
          crs: const Epsg3857(),
          center: centre,
          zoom: zoom,
          rotation: 0,
          nonRotatedSize: tilt.mapSize,
        ),
        tilt: tilt,
        buildings: [house(height)],
        palette: BuildingPalette.light,
      );
      final rec = ui.PictureRecorder();
      p.paint(Canvas(rec), tilt.mapSize);
      rec.endRecording().dispose();
      return p.lastTriangles;
    }

    expect(drawn(18, 30), greaterThan(0)); // a normal house
    expect(drawn(20, 400), 0); // a tower right in front of the eye
  });
}
