import 'package:app/features/weather/weather_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weather_helpers.dart';

void main() {
  test('parses current weather and the hours after the current one', () {
    final w = SpotWeather.fromOpenMeteo(openMeteoSample());
    expect(w.time, DateTime(2026, 11, 4, 14, 15));
    expect(w.temperature, 8.4);
    expect(w.code, 61);
    expect(w.isDay, isTrue);
    expect(w.windKmh, 14.6);
    expect(w.precipitationMm, 0.3);
    // chance of the current hour (14:00), not of the next one
    expect(w.precipitationChance, 70);
    // 15:00 .. 19:00; 20:00 has no temperature and is left out
    expect(w.hours.map((h) => h.time.hour), [15, 16, 17, 18, 19]);
    expect(w.hours.first.temperature, 8.1);
    expect(w.hours.first.code, 63);
    expect(w.hours.first.precipitationChance, 80);
    expect(w.hours.first.isDay, isTrue);
    expect(w.hours[2].isDay, isFalse);
  });

  test('without hourly data the current values are still enough', () {
    final j = openMeteoSample()..remove('hourly');
    final w = SpotWeather.fromOpenMeteo(j);
    expect(w.hours, isEmpty);
    expect(w.precipitationChance, isNull);
    expect(w.temperature, 8.4);
  });

  test('an answer without current weather is an error', () {
    expect(
      () => SpotWeather.fromOpenMeteo({'hourly': {}}),
      throwsFormatException,
    );
    final j = openMeteoSample();
    (j['current'] as Map).remove('temperature_2m');
    expect(() => SpotWeather.fromOpenMeteo(j), throwsFormatException);
  });

  test('asks Open-Meteo for the spot, without our login', () async {
    final a = WeatherAdapter();
    final repo = OpenMeteoWeatherRepository(dio: Dio()..httpClientAdapter = a);
    final w = await repo.forSpot((spotId: 7, lat: 52.520008, lon: 13.404954));
    expect(w.temperature, 8.4);
    final o = a.seen.single;
    expect(o.uri.toString(), startsWith(kOpenMeteoUrl));
    expect(o.uri.host, 'api.open-meteo.com');
    final q = o.uri.queryParameters;
    expect(q['latitude'], '52.5200');
    expect(q['longitude'], '13.4050');
    expect(q['current'], contains('temperature_2m'));
    expect(q['current'], contains('weather_code'));
    expect(q['current'], contains('wind_speed_10m'));
    expect(q['current'], contains('precipitation'));
    expect(q['hourly'], contains('precipitation_probability'));
    expect(q['timezone'], 'auto');
    expect(q['forecast_hours'], '7');
    expect(
      o.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('authorization')),
    );
  });

  test('keeps an answer per spot for 15 minutes', () async {
    final a = WeatherAdapter();
    var now = DateTime(2026, 11, 4, 14);
    final repo = OpenMeteoWeatherRepository(
      dio: Dio()..httpClientAdapter = a,
      clock: () => now,
    );
    await repo.forSpot((spotId: 1, lat: 52, lon: 13));
    await repo.forSpot((spotId: 1, lat: 52, lon: 13));
    expect(a.seen, hasLength(1));
    await repo.forSpot((spotId: 2, lat: 48, lon: 11));
    expect(a.seen, hasLength(2));

    now = now.add(const Duration(minutes: 14));
    await repo.forSpot((spotId: 1, lat: 52, lon: 13));
    expect(a.seen, hasLength(2));
    now = now.add(const Duration(minutes: 2));
    await repo.forSpot((spotId: 1, lat: 52, lon: 13));
    expect(a.seen, hasLength(3));
  });

  test('a failure is not kept: the next visit asks again', () async {
    final a = WeatherAdapter(status: 503, body: {'error': true});
    final repo = OpenMeteoWeatherRepository(dio: Dio()..httpClientAdapter = a);
    await expectLater(
      repo.forSpot((spotId: 1, lat: 52, lon: 13)),
      throwsA(isA<DioException>()),
    );
    a
      ..status = 200
      ..body = openMeteoSample();
    final w = await repo.forSpot((spotId: 1, lat: 52, lon: 13));
    expect(w.temperature, 8.4);
    expect(a.seen, hasLength(2));
  });
}
