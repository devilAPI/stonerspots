import 'package:app/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> json(Object? cover) => {
  'id': 1,
  'title': 'Bench',
  'category': 'bench',
  'lat': 48.1,
  'lon': 11.6,
  'cover_url': ?cover,
};

void main() {
  test('the API sends an empty cover_url for spots without photos: that is no photo', () {
    expect(Spot.fromJson(json('')).coverUrl, isNull);
    expect(Spot.fromJson(json('   ')).coverUrl, isNull);
  });
  test('a missing or null cover_url is no photo', () {
    expect(Spot.fromJson(json(null)).coverUrl, isNull);
  });
  test('a real cover_url is kept', () {
    expect(
      Spot.fromJson(json('http://h/api/v1/media/a.jpg')).coverUrl,
      'http://h/api/v1/media/a.jpg',
    );
  });
}
