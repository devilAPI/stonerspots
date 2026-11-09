import 'package:app/features/zones/germany.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Same places as backend/internal/zones/germany_test.go, checked against
  // the full-resolution OSM boundary.
  const cases = <String, (double, double, bool)>{
    'Munich': (48.1374, 11.5755, true),
    'Berlin': (52.52, 13.405, true),
    'Lörrach': (47.6156, 7.6614, true),
    'Weil am Rhein': (47.5947, 7.6206, true),
    'Kehl': (48.5726, 7.8153, true),
    'Freilassing': (47.8406, 12.9772, true),
    'Konstanz': (47.6603, 9.1758, true),
    'Görlitz': (51.1526, 14.9872, true),
    'Frankfurt (Oder)': (52.3471, 14.5506, true),
    'Flensburg': (54.7836, 9.4321, true),
    'Helgoland': (54.1817, 7.8856, true),
    'Büsingen (exclave)': (47.6967, 8.6900, true),
    'Aachen': (50.7753, 6.0839, true),
    'Westerland (Sylt)': (54.9079, 8.3105, true),
    'Garmisch': (47.4917, 11.0955, true),
    'Passau': (48.5667, 13.4319, true),
    'Basel': (47.5596, 7.5886, false),
    'Strasbourg': (48.5734, 7.7521, false),
    'Salzburg': (47.8095, 13.0550, false),
    'Kreuzlingen': (47.6447, 9.1772, false),
    'Słubice': (52.3497, 14.5603, false),
    'Schaffhausen': (47.6973, 8.6349, false),
    'Vaals': (50.7703, 6.0186, false),
    'Zgorzelec': (51.1500, 15.0083, false),
    'Jungholz (AT)': (47.5747, 10.4486, false),
    'Riezlern (AT)': (47.3583, 10.1856, false),
    'Vienna': (48.2082, 16.3738, false),
    'Paris': (48.8566, 2.3522, false),
    'Copenhagen': (55.6761, 12.5683, false),
    'Prague': (50.0755, 14.4378, false),
    'Porto': (41.1373, -8.6094, false),
    'Sydney': (-33.8688, 151.2093, false),
  };
  cases.forEach((name, c) {
    test('$name: ${c.$3 ? 'in' : 'not in'} Germany', () {
      expect(inGermany(LatLng(c.$1, c.$2)), c.$3);
    });
  });

  test('boxes: inside, outside, across the border', () {
    // Munich tile, Vienna tile, the Konstanz/Kreuzlingen tile, Europe
    expect(touchesGermany(48.12, 11.56, 48.14, 11.58), isTrue);
    expect(touchesGermany(48.20, 16.36, 48.22, 16.38), isFalse);
    expect(touchesGermany(47.64, 9.16, 47.66, 9.18), isTrue);
    expect(touchesGermany(47.64, 9.16, 47.645, 9.165), isFalse);
    expect(touchesGermany(40, 0, 60, 20), isTrue);
  });

  test('polyline decoding (Google example)', () {
    final p = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(p.map((x) => [x.latitude, x.longitude]), [
      [38.5, -120.2],
      [40.7, -120.95],
      [43.252, -126.453],
    ]);
  });
}
