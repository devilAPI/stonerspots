import 'package:app/features/zones/zone_tiles.dart';
import 'package:app/features/zones/zone_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'zone_fixtures.dart';

void main() {
  group('pedestrian zone hours (German time)', () {
    test('winter: UTC+1', () {
      // 15 Jan, 05:59 UTC = 06:59 CET
      expect(pedestrianBanActive(DateTime.utc(2026, 1, 15, 5, 59)), isFalse);
      expect(pedestrianBanActive(DateTime.utc(2026, 1, 15, 6, 0)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 1, 15, 18, 59)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 1, 15, 19, 0)), isFalse);
    });

    test('summer: UTC+2', () {
      expect(pedestrianBanActive(DateTime.utc(2026, 7, 1, 4, 59)), isFalse);
      expect(pedestrianBanActive(DateTime.utc(2026, 7, 1, 5, 0)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 7, 1, 17, 59)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 7, 1, 18, 0)), isFalse);
    });

    test('summer time starts last Sunday of March, 01:00 UTC', () {
      // 29 March 2026 is the last Sunday in March
      expect(isGermanSummerTime(DateTime.utc(2026, 3, 29, 0, 59)), isFalse);
      expect(isGermanSummerTime(DateTime.utc(2026, 3, 29, 1, 0)), isTrue);
      expect(germanTime(DateTime.utc(2026, 3, 29, 0, 59)).hour, 1);
      expect(germanTime(DateTime.utc(2026, 3, 29, 1, 0)).hour, 3);
      // 05:30 UTC that morning is 07:30 CEST: already forbidden (with
      // winter time it would still be 06:30)
      expect(pedestrianBanActive(DateTime.utc(2026, 3, 29, 5, 30)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 3, 28, 5, 30)), isFalse);
    });

    test('summer time ends last Sunday of October, 01:00 UTC', () {
      // 25 October 2026 is the last Sunday in October
      expect(isGermanSummerTime(DateTime.utc(2026, 10, 25, 0, 59)), isTrue);
      expect(isGermanSummerTime(DateTime.utc(2026, 10, 25, 1, 0)), isFalse);
      // 05:30 UTC: 06:30 CET, allowed (07:30 the day before)
      expect(pedestrianBanActive(DateTime.utc(2026, 10, 25, 5, 30)), isFalse);
      expect(pedestrianBanActive(DateTime.utc(2026, 10, 24, 5, 30)), isTrue);
      // 18:30 UTC: 19:30 CET, still forbidden (20:30 the day before)
      expect(pedestrianBanActive(DateTime.utc(2026, 10, 25, 18, 30)), isTrue);
      expect(pedestrianBanActive(DateTime.utc(2026, 10, 24, 18, 30)), isFalse);
    });

    test('the device time zone does not matter', () {
      final t = DateTime.utc(2026, 7, 1, 5, 30);
      expect(pedestrianBanActive(t.toLocal()), pedestrianBanActive(t));
    });

    test('next change: 7 or 20 h German time, across a DST switch', () {
      expect(
        nextPedestrianChange(DateTime.utc(2026, 1, 15, 10)),
        DateTime.utc(2026, 1, 15, 19),
      );
      expect(
        nextPedestrianChange(DateTime.utc(2026, 1, 15, 20)),
        DateTime.utc(2026, 1, 16, 6),
      );
      // night of the spring switch: 07:00 CEST = 05:00 UTC
      expect(
        nextPedestrianChange(DateTime.utc(2026, 3, 28, 23, 30)),
        DateTime.utc(2026, 3, 29, 5),
      );
      // night of the autumn switch: 07:00 CET = 06:00 UTC
      expect(
        nextPedestrianChange(DateTime.utc(2026, 10, 24, 22, 30)),
        DateTime.utc(2026, 10, 25, 6),
      );
    });
  });

  group('tiles (same grid as the server)', () {
    test('a point and its tile', () {
      final t = ZoneTileId.at(48.137, 11.575);
      expect(t, const ZoneTileId(2406, 578));
      expect(t.query, {
        'south': '48.120000',
        'west': '11.560000',
        'north': '48.140000',
        'east': '11.580000',
      });
      expect(ZoneTileId.at(-0.001, -0.001), const ZoneTileId(-1, -1));
      // on the edge: the tile above/right
      expect(ZoneTileId.at(48.12, 11.56), const ZoneTileId(2406, 578));
    });

    test('covering a box', () {
      const t = ZoneTileId(2406, 578);
      expect(tilesCovering(t.south, t.west, t.north, t.east), [t]);
      final many = tilesCovering(48.135, 11.575, 48.145, 11.615);
      expect(many, hasLength(6));
      expect(many.first, const ZoneTileId(2406, 578));
      expect(many.last, const ZoneTileId(2407, 580));
    });

    test('around a point: one tile, more near an edge', () {
      expect(tilesAround(base, 120), [ZoneTileId.at(48.13, 11.57)]);
      // 50 m south of the edge at 48.14
      final nearEdge = LatLng(48.14 - 50 / 111320, 11.57);
      expect(tilesAround(nearEdge, 120), [
        const ZoneTileId(2406, 578),
        const ZoneTileId(2407, 578),
      ]);
      // near a corner: four tiles
      expect(tilesAround(const LatLng(48.1399, 11.5799), 120), hasLength(4));
    });
  });
}
