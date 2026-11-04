import 'package:app/features/zones/zone_geo.dart';
import 'package:app/features/zones/zone_models.dart';
import 'package:app/features/zones/zone_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'zone_fixtures.dart';

void main() {
  const haversine = Distance(calculator: Haversine(), roundResult: false);

  test('local frame distances match great-circle distances', () {
    // Marienplatz to Karlsplatz (Stachus), about 640 m
    const a = LatLng(48.13743, 11.57549);
    const b = LatLng(48.13906, 11.56614);
    final d = distanceToLine(a, [b]);
    final h = haversine.as(LengthUnit.Meter, a, b).toDouble();
    expect(h, closeTo(718, 5));
    expect(d, closeTo(h, 0.5));
    // north-south: 0.001° latitude
    expect(
      distanceToLine(const LatLng(48, 11), [const LatLng(48.001, 11)]),
      closeTo(111.32, 0.01),
    );
    // east-west shrinks with cos(latitude)
    expect(
      distanceToLine(const LatLng(48, 11), [const LatLng(48, 11.001)]),
      closeTo(111.32 * 0.66913, 0.02),
    );
    // offset() inverts the projection
    expect(distanceToLine(base, [at(30, 40)]), closeTo(50, 0.01));
  });

  test('distance to a line is to the nearest segment, not a vertex', () {
    final l = [at(-100, 0), at(100, 0)];
    expect(distanceToLine(at(0, 70), l), closeTo(70, 0.01));
    expect(distanceToLine(at(130, 40), l), closeTo(50, 0.01)); // past the end
    final z = line('way/1', ZoneKind.sports, l);
    expect(distanceToZone(at(0, -30), z), closeTo(30, 0.01));
  });

  test('polygon: 0 inside, distance to the outline outside', () {
    final z = square('way/2', ZoneKind.playground, size: 40);
    expect(distanceToZone(base, z), 0);
    expect(distanceToZone(at(19, -19), z), 0);
    expect(distanceToZone(at(0, 50), z), closeTo(30, 0.01));
    expect(distanceToZone(at(23, 24), z), closeTo(5, 0.01)); // corner 3-4-5
    expect(pointInRing(at(0, 21), z.parts.first), isFalse);
  });

  test('the 100 m zone holds at 99 m and ends at 101 m', () {
    final pg = square('way/3', ZoneKind.playground, size: 40); // edge at 20 m
    expect(zonesAt(at(0, 20 + 99), [pg]), hasLength(1));
    expect(zonesAt(at(0, 20 + 101), [pg]), isEmpty);
    expect(zonesAt(at(-(20.0 + 99), 0), [pg]), hasLength(1));
    expect(zonesAt(at(-(20.0 + 101), 0), [pg]), isEmpty);

    final school = point('node/4', ZoneKind.school, at(500, 0));
    expect(zonesAt(at(500, 99), [school]), hasLength(1));
    expect(zonesAt(at(500, 101), [school]), isEmpty);
    // diagonal from a node (checks the east-west scale)
    expect(zonesAt(at(500 + 70, 70), [school]), hasLength(1)); // 98.99 m
    expect(zonesAt(at(500 + 72, 72), [school]), isEmpty); // 101.8 m

    final track = line('way/5', ZoneKind.sports, [at(-50, -300), at(50, -300)]);
    expect(zonesAt(at(0, -300 + 99), [track]), hasLength(1));
    expect(zonesAt(at(0, -300 + 101), [track]), isEmpty);
  });

  test('pedestrian zones are the area itself; explicit bans too', () {
    final fz = square('way/6', ZoneKind.pedestrian, size: 40);
    expect(fz.radius, 0);
    expect(zonesAt(at(0, 19), [fz]), hasLength(1));
    expect(zonesAt(at(0, 25), [fz]), isEmpty);
    final street = line('way/7', ZoneKind.pedestrian, [
      at(-100, 0),
      at(100, 0),
    ]);
    expect(zonesAt(at(0, 4), [street]), hasLength(1));
    expect(zonesAt(at(0, 6), [street]), isEmpty);
    final ban = point('node/8', ZoneKind.explicit, base);
    expect(zonesAt(at(0, 14), [ban]), hasLength(1));
    expect(zonesAt(at(0, 16), [ban]), isEmpty);
  });

  test('status: facility beats pedestrian zone, nearest first', () {
    final zones = [
      square('way/1', ZoneKind.pedestrian, size: 400),
      point('node/2', ZoneKind.playground, at(60, 0), name: 'Spielplatz A'),
      point('node/3', ZoneKind.school, at(40, 0)),
    ];
    final s = zoneStatusAt(base, zones);
    expect(s.verdict, ZoneVerdict.forbidden);
    expect(s.hit!.zone.id, 'node/3');
    expect(s.hit!.distance, closeTo(40, 0.01));
    expect(zoneStatusAt(base, [zones.first]).verdict, ZoneVerdict.pedestrian);
    expect(zoneStatusAt(at(0, 500), zones).verdict, ZoneVerdict.clear);
  });

  test('parses the API format and skips unknown kinds and geometries', () {
    final d = ZoneData.fromJson({
      'zones': [
        {
          'id': 'node/1',
          'kind': 'school',
          'name': 'Grundschule',
          'geometry': {
            'type': 'Point',
            'coordinates': [48.13, 11.57],
          },
        },
        {
          'id': 'way/2',
          'kind': 'pedestrian',
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [48.13, 11.57],
              [48.131, 11.571],
            ],
          },
          'access_hours': '7-20',
        },
        {
          'id': 'relation/3',
          'kind': 'sports',
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              [
                [
                  [48.1, 11.5],
                  [48.1, 11.6],
                  [48.2, 11.6],
                  [48.1, 11.5],
                ],
              ],
              [
                [
                  [48.3, 11.5],
                  [48.3, 11.6],
                  [48.4, 11.6],
                  [48.3, 11.5],
                ],
              ],
            ],
          },
        },
        {
          'id': 'way/4',
          'kind': 'brewery',
          'geometry': {
            'type': 'Point',
            'coordinates': [48, 11],
          },
        },
        {
          'id': 'way/5',
          'kind': 'school',
          'geometry': {'type': 'Circle', 'coordinates': []},
        },
        {
          'id': 'way/6',
          'kind': 'school',
          'geometry': {'type': 'Point', 'coordinates': 'x'},
        },
      ],
      'stale': true,
    });
    expect(d.stale, isTrue);
    expect(d.zones.map((z) => z.id), ['node/1', 'way/2', 'relation/3']);
    expect(d.zones[0].shape, ZoneShape.point);
    expect(d.zones[0].name, 'Grundschule');
    expect(d.zones[1].shape, ZoneShape.line);
    expect(d.zones[2].shape, ZoneShape.polygon);
    expect(d.zones[2].parts, hasLength(2));
    expect(d.zones[2].north, 48.4);
  });
}
