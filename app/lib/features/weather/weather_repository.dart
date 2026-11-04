import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Weather now and in the next hours at one place.
class SpotWeather {
  const SpotWeather({
    required this.time,
    required this.temperature,
    required this.code,
    required this.isDay,
    required this.windKmh,
    required this.precipitationMm,
    required this.precipitationChance,
    required this.hours,
  });

  /// Local time at the spot (Open-Meteo answers with `timezone=auto`).
  final DateTime time;
  final double temperature;
  final int? code;
  final bool isDay;
  final double windKmh;
  final double precipitationMm;

  /// Chance of precipitation in the current hour, in percent; null if unknown.
  final int? precipitationChance;

  /// The hours after the current one, in order.
  final List<HourlyWeather> hours;

  /// Parses an Open-Meteo `/v1/forecast` answer. Throws [FormatException]
  /// when the current values are missing.
  factory SpotWeather.fromOpenMeteo(Map<String, dynamic> j, {int hours = 6}) {
    final cur = j['current'];
    if (cur is! Map) throw const FormatException('no current weather');
    final time = DateTime.tryParse('${cur['time']}');
    final temp = _num(cur['temperature_2m']);
    if (time == null || temp == null) {
      throw const FormatException('incomplete current weather');
    }
    final h = j['hourly'] is Map ? j['hourly'] as Map : const {};
    List<dynamic> col(String k) => h[k] is List ? h[k] as List : const [];
    final times = col('time');
    final temps = col('temperature_2m');
    final codes = col('weather_code');
    final probs = col('precipitation_probability');
    final days = col('is_day');
    T? at<T>(List<dynamic> l, int i, T? Function(Object?) f) =>
        i < l.length ? f(l[i]) : null;

    final thisHour = DateTime(time.year, time.month, time.day, time.hour);
    int? chance;
    final next = <HourlyWeather>[];
    for (var i = 0; i < times.length; i++) {
      final t = DateTime.tryParse('${times[i]}');
      if (t == null) continue;
      final prob = at(probs, i, _num)?.round();
      if (!t.isAfter(thisHour)) {
        if (t == thisHour) chance = prob;
        continue;
      }
      final tt = at(temps, i, _num);
      if (tt == null || next.length >= hours) continue;
      next.add(
        HourlyWeather(
          time: t,
          temperature: tt,
          code: at(codes, i, _num)?.toInt(),
          precipitationChance: prob,
          isDay: at(days, i, _num) != 0,
        ),
      );
    }
    // Without an entry for this hour the nearest coming one stands in.
    chance ??= next.isEmpty ? null : next.first.precipitationChance;
    return SpotWeather(
      time: time,
      temperature: temp,
      code: _num(cur['weather_code'])?.toInt(),
      isDay: _num(cur['is_day']) != 0,
      windKmh: _num(cur['wind_speed_10m']) ?? 0,
      precipitationMm: _num(cur['precipitation']) ?? 0,
      precipitationChance: chance,
      hours: next,
    );
  }
}

class HourlyWeather {
  const HourlyWeather({
    required this.time,
    required this.temperature,
    required this.code,
    required this.precipitationChance,
    this.isDay = true,
  });

  final DateTime time;
  final double temperature;
  final int? code;
  final int? precipitationChance;
  final bool isDay;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Which forecast to load: the spot (cache key) and where it is.
typedef WeatherQuery = ({int spotId, double lat, double lon});

abstract class WeatherRepository {
  Future<SpotWeather> forSpot(WeatherQuery q);
}

const kOpenMeteoUrl = 'https://api.open-meteo.com/v1/forecast';

/// Open-Meteo (no key, CORS allowed, so it works on the web too). Uses its
/// own Dio: the API client would send our login token to a third party.
/// Answers are kept per spot for [ttl] in memory.
class OpenMeteoWeatherRepository implements WeatherRepository {
  OpenMeteoWeatherRepository({
    Dio? dio,
    this.ttl = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _clock = clock ?? DateTime.now;

  final Dio _dio;
  final Duration ttl;
  final DateTime Function() _clock;
  final _cache = <int, ({DateTime at, Future<SpotWeather> value})>{};

  @override
  Future<SpotWeather> forSpot(WeatherQuery q) {
    final now = _clock();
    final hit = _cache[q.spotId];
    if (hit != null && now.difference(hit.at) < ttl) return hit.value;
    final value = _fetch(q);
    _cache[q.spotId] = (at: now, value: value);
    // A failure is not kept: the next visit tries again.
    value.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[q.spotId]?.value, value)) _cache.remove(q.spotId);
      },
    );
    return value;
  }

  Future<SpotWeather> _fetch(WeatherQuery q) async {
    final res = await _dio.get<Map<String, dynamic>>(
      kOpenMeteoUrl,
      queryParameters: {
        'latitude': q.lat.toStringAsFixed(4),
        'longitude': q.lon.toStringAsFixed(4),
        'current':
            'temperature_2m,weather_code,wind_speed_10m,precipitation,is_day',
        'hourly':
            'temperature_2m,weather_code,precipitation_probability,is_day',
        'timezone': 'auto',
        'forecast_hours': 7,
      },
    );
    final data = res.data;
    if (data == null) throw const FormatException('empty answer');
    return SpotWeather.fromOpenMeteo(data);
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => OpenMeteoWeatherRepository(),
);

final spotWeatherProvider = FutureProvider.autoDispose
    .family<SpotWeather, WeatherQuery>(
      (ref, q) => ref.watch(weatherRepositoryProvider).forSpot(q),
    );
