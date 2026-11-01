import 'dart:convert';

import 'package:app/core/models.dart';
import 'package:app/features/home_widgets/nearest_spot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

const munich = LatLng(48.1372, 11.5755);

Spot spot(
  int id, {
  required double lat,
  required double lon,
  double ratingAvg = 0,
  int ratingCount = 0,
  List<SpotTag> tags = const [],
}) => Spot(
  id: id,
  title: 'Spot $id',
  lat: lat,
  lon: lon,
  ratingAvg: ratingAvg,
  ratingCount: ratingCount,
  tags: tags,
);

void main() {
  final near = spot(1, lat: 48.14, lon: 11.58); // about 450 m
  final mid = spot(2, lat: 48.2, lon: 11.6); // about 7 km
  final far = spot(3, lat: 52.52, lon: 13.4); // Berlin

  group('nearestSpot', () {
    test('picks the closest one, whatever the order', () {
      expect(nearestSpot(munich, [far, near, mid])!.spot, near);
      expect(nearestSpot(munich, [near, far, mid])!.spot, near);
    });

    test('gives the distance in metres', () {
      expect(nearestSpot(munich, [mid])!.meters, closeTo(7200, 300));
    });

    test('is null without spots', () {
      expect(nearestSpot(munich, const []), isNull);
    });
  });

  group('formatDistance', () {
    test('metres in tens', () {
      expect(formatDistance(4, 'de'), '0 m');
      expect(formatDistance(847, 'de'), '850 m');
      expect(formatDistance(994, 'en'), '990 m');
    });

    test('one decimal below ten km, with the language\'s separator', () {
      expect(formatDistance(1234, 'de'), '1,2 km');
      expect(formatDistance(1234, 'en'), '1.2 km');
      expect(formatDistance(995, 'en'), '1.0 km');
    });

    test('whole km from ten', () {
      expect(formatDistance(9950, 'de'), '10 km');
      expect(formatDistance(23456, 'de'), '23 km');
    });
  });

  group('payload', () {
    test('holds the id and display texts', () {
      final payload = SpotPayload((
        spot: spot(
          7,
          lat: 48,
          lon: 11,
          ratingAvg: 4.5,
          ratingCount: 3,
          tags: const [SpotTag.quiet, SpotTag.view],
        ),
        meters: 1500,
      ), 'de');
      expect(jsonDecode(payload.encode()), {
        'state': 'spot',
        'id': 7,
        'name': 'Spot 7',
        'meta': '1,5 km · ★ 4.5',
        'tags': 'Aussicht · Ruhig',
      });
    });

    test('never carries coordinates', () {
      final json = SpotPayload((
        spot: spot(7, lat: 48.1111, lon: 11.2222),
        meters: 1500,
      ), 'de').encode();
      expect(json, isNot(contains('48.1')));
      expect(json, isNot(contains('11.2')));
    });

    test('leaves out a rating nobody gave and lists at most three tags', () {
      final payload = SpotPayload((
        spot: spot(
          7,
          lat: 48,
          lon: 11,
          tags: const [
            SpotTag.lit,
            SpotTag.water,
            SpotTag.roof,
            SpotTag.seating,
          ],
        ),
        meters: 40,
      ), 'en');
      expect(payload.meta, '40 m');
      expect(payload.tags, 'Roof · Seating · Water nearby');
    });

    test('empty states name only the state', () {
      expect(const NoLocationPayload().toJson(), {'state': 'no_location'});
      expect(const NoSpotsPayload().toJson(), {'state': 'no_spots'});
    });
  });

  group('NearestSpotTracker', () {
    late NearestSpotTracker tracker;
    setUp(() => tracker = NearestSpotTracker(languageCode: () => 'de'));

    int? idOf(NearestSpotPayload? p) => (p as SpotPayload?)?.id;

    test('waits for both a position and spots', () {
      expect(tracker.onSpots([near], filtered: false), isNull);
      expect(idOf(tracker.onLookup(munich)), near.id);

      tracker = NearestSpotTracker(languageCode: () => 'de');
      expect(tracker.onLookup(munich), isNull);
      expect(idOf(tracker.onSpots([near], filtered: false)), near.id);
    });

    test('keeps the closest spot when the map moves elsewhere', () {
      tracker.onLookup(munich);
      tracker.onSpots([near, mid], filtered: false);
      expect(idOf(tracker.onSpots([far], filtered: false)), near.id);
      expect(idOf(tracker.onSpots(const [], filtered: false)), near.id);
    });

    test('replaces it by a closer one', () {
      tracker.onLookup(munich);
      tracker.onSpots([mid], filtered: false);
      expect(idOf(tracker.onSpots([near], filtered: false)), near.id);
    });

    test('starts over when the user has moved', () {
      tracker.onLookup(munich);
      tracker.onSpots([near], filtered: false);
      final hamburg = spot(4, lat: 53.55, lon: 9.99);
      tracker.onSpots([hamburg], filtered: false);
      expect(idOf(tracker.onLookup(const LatLng(53.55, 10.0))), hamburg.id);
    });

    test('a small GPS jitter does not start over', () {
      tracker.onLookup(munich);
      tracker.onSpots([near], filtered: false);
      tracker.onSpots([far], filtered: false);
      expect(idOf(tracker.onLookup(const LatLng(48.1373, 11.5755))), near.id);
    });

    test('no spots around: says so, unless a filter hid them', () {
      tracker.onLookup(munich);
      expect(tracker.onSpots(const [], filtered: true), isNull);
      expect(tracker.onSpots(const [], filtered: false), isA<NoSpotsPayload>());
    });

    test('a failed lookup clears the spot', () {
      tracker.onLookup(munich);
      tracker.onSpots([near], filtered: false);
      expect(tracker.onLookup(null), isA<NoLocationPayload>());
      expect(tracker.onSpots([near], filtered: false), isNull);
    });
  });
}
