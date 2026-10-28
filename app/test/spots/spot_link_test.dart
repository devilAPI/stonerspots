import 'package:app/features/spots/spot_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('points at the spot route of the web app', () {
    expect(
      spotLink(12, base: Uri.parse('https://devilapi.github.io/stonerspots/')),
      Uri.parse('https://devilapi.github.io/stonerspots/#/spot/12'),
    );
  });

  test('keeps the sub-path and drops what the page had after it', () {
    expect(
      spotLink(
        3,
        base: Uri.parse(
          'https://devilapi.github.io/stonerspots/dev/?x=1#/feed',
        ),
      ),
      Uri.parse('https://devilapi.github.io/stonerspots/dev/#/spot/3'),
    );
  });

  test('keeps a port and adds a missing slash', () {
    expect(
      spotLink(5, base: Uri.parse('http://localhost:8081')),
      Uri.parse('http://localhost:8081/#/spot/5'),
    );
  });
}
