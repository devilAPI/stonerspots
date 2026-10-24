import 'package:app/features/spots/maps_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('google maps link points at the exact coordinates', () {
    final u = googleMapsUri(48.1234567, 11.6543210);
    expect(u.scheme, 'https');
    expect(u.host, 'www.google.com');
    expect(u.path, '/maps/search/');
    expect(u.queryParameters['api'], '1');
    expect(u.queryParameters['query'], '48.1234567,11.654321');
  });

  test('negative coordinates are kept', () {
    expect(
      googleMapsUri(-33.5, -70.25).queryParameters['query'],
      '-33.5,-70.25',
    );
  });
}
