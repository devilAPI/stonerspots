import 'package:app/core/coordinates.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const lat = 48.1234;
  const lon = 11.5678;
  final dmsLat = 48 + 2 / 60 + 19.3 / 3600;
  final dmsLon = 11 + 30 / 60 + 50.2 / 3600;

  final ok = <String, List<double>>{
    '48.1234, 11.5678': [lat, lon],
    '48.1234 11.5678': [lat, lon],
    '48.1234,11.5678': [lat, lon],
    '48.1234;11.5678': [lat, lon],
    '(48.1234, 11.5678)': [lat, lon],
    '  48.1234, 11.5678  ': [lat, lon],
    '\t48.1234,\t11.5678\t': [lat, lon],
    '48,1234 11,5678': [lat, lon],
    '48,1234; 11,5678': [lat, lon],
    '48.1234 N, 11.5678 E': [lat, lon],
    'N48.1234 E11.5678': [lat, lon],
    '48.1234N 11.5678E': [lat, lon],
    '48.1234 S, 11.5678 W': [-lat, -lon],
    'S48.1234 W11.5678': [-lat, -lon],
    '11.5678 E, 48.1234 N': [lat, lon],
    '48°02\'19.3"N 11°30\'50.2"E': [dmsLat, dmsLon],
    '48°02′19.3″N 11°30′50.2″E': [dmsLat, dmsLon],
    '48°02’19.3”N 11°30’50.2”E': [dmsLat, dmsLon],
    '48°2.5\'N 11°30.2\'E': [48 + 2.5 / 60, 11 + 30.2 / 60],
    'N 48° 02\' 19.3" E 11° 30\' 50.2"': [dmsLat, dmsLon],
    'https://www.google.com/maps/@48.1234,11.5678,17z': [lat, lon],
    'https://www.google.com/maps/place/Foo/@48.1,11.5,17z/data=!3m1!4b1!4d..!3d48.1234!4d11.5678':
        [lat, lon],
    'https://www.google.com/maps?q=48.1234,11.5678': [lat, lon],
    'https://www.google.com/maps?ll=48.1234,11.5678': [lat, lon],
    'https://www.google.com/maps/search/?api=1&query=48.1234,11.5678': [
      lat,
      lon,
    ],
    'https://www.google.com/maps/search/?api=1&query=48.1234%2C11.5678': [
      lat,
      lon,
    ],
    'https://www.openstreetmap.org/#map=17/48.1234/11.5678': [lat, lon],
    'https://www.openstreetmap.org/?mlat=48.1234&mlon=11.5678#map=17/1/2': [
      lat,
      lon,
    ],
    'geo:48.1234,11.5678': [lat, lon],
    'geo:48.1234,11.5678?z=17': [lat, lon],
    // Unlabelled pairs are lat, lon anywhere in the world...
    '11.5678, 48.1234': [lon, lat],
    '40.7128, -74.0060': [40.7128, -74.0060],
    '-33.8688, 151.2093': [-33.8688, 151.2093],
    // ...and swapped only when lat, lon cannot be right.
    '151.2093, -33.8688': [-33.8688, 151.2093],
    '95.0, 11.5': [11.5, 95.0],
  };

  ok.forEach((input, want) {
    test('parses $input', () {
      final p = parseCoordinates(input);
      expect(p, isNotNull);
      expect(p!.latitude, closeTo(want[0], 1e-9));
      expect(p.longitude, closeTo(want[1], 1e-9));
    });
  });

  for (final input in [
    '',
    '   ',
    'Marienplatz 1',
    'Hauptstraße 12, 80331 München',
    '48.1234',
    '48.1 11.5 3.2',
    '200, 300',
    'https://maps.app.goo.gl/xyz',
    'https://goo.gl/maps/abc',
  ]) {
    test('rejects "$input"', () => expect(parseCoordinates(input), isNull));
  }
}
