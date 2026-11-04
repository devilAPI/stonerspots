import 'dart:convert';
import 'dart:typed_data';

import 'package:app/features/weather/weather_repository.dart';
import 'package:dio/dio.dart';

/// A trimmed real answer of Open-Meteo for Berlin, at 14:15 local time.
Map<String, dynamic> openMeteoSample() => {
  'latitude': 52.52,
  'longitude': 13.41,
  'timezone': 'Europe/Berlin',
  'utc_offset_seconds': 3600,
  'current': {
    'time': '2026-11-04T14:15',
    'interval': 900,
    'temperature_2m': 8.4,
    'weather_code': 61,
    'wind_speed_10m': 14.6,
    'precipitation': 0.3,
    'is_day': 1,
  },
  'hourly': {
    'time': [
      '2026-11-04T14:00',
      '2026-11-04T15:00',
      '2026-11-04T16:00',
      '2026-11-04T17:00',
      '2026-11-04T18:00',
      '2026-11-04T19:00',
      '2026-11-04T20:00',
    ],
    'temperature_2m': [8.4, 8.1, 7.6, 6.9, 6.2, 5.8, null],
    'weather_code': [61, 63, 3, 2, 0, 0, 0],
    'precipitation_probability': [70, 80, 30, 10, 0, 0, 0],
    'is_day': [1, 1, 1, 0, 0, 0, 0],
  },
};

class WeatherAdapter implements HttpClientAdapter {
  WeatherAdapter({this.status = 200, Object? body})
    : body = body ?? openMeteoSample();

  int status;
  Object body;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A repository answering from memory, or failing with [error].
class FakeWeather implements WeatherRepository {
  FakeWeather({this.error});

  Object? error;
  final asked = <WeatherQuery>[];

  @override
  Future<SpotWeather> forSpot(WeatherQuery q) async {
    asked.add(q);
    if (error != null) throw error!;
    return SpotWeather.fromOpenMeteo(openMeteoSample());
  }
}
