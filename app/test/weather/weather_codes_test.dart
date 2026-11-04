import 'package:app/features/weather/weather_codes.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every WMO code Open-Meteo sends has a condition', () {
    const used = [
      0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, //
      71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99,
    ];
    for (final code in used) {
      expect(
        weatherCondition(code),
        isNot(WeatherCondition.unknown),
        reason: 'code $code',
      );
    }
    for (final code in [null, -1, 4, 50, 100]) {
      expect(weatherCondition(code), WeatherCondition.unknown);
    }
  });

  test('codes map to the right condition', () {
    expect(weatherCondition(0), WeatherCondition.clear);
    expect(weatherCondition(2), WeatherCondition.partlyCloudy);
    expect(weatherCondition(3), WeatherCondition.overcast);
    expect(weatherCondition(48), WeatherCondition.fog);
    expect(weatherCondition(53), WeatherCondition.drizzle);
    expect(weatherCondition(57), WeatherCondition.freezingDrizzle);
    expect(weatherCondition(61), WeatherCondition.rainLight);
    expect(weatherCondition(63), WeatherCondition.rain);
    expect(weatherCondition(65), WeatherCondition.rainHeavy);
    expect(weatherCondition(67), WeatherCondition.freezingRain);
    expect(weatherCondition(73), WeatherCondition.snow);
    expect(weatherCondition(77), WeatherCondition.snowGrains);
    expect(weatherCondition(81), WeatherCondition.showers);
    expect(weatherCondition(82), WeatherCondition.showersHeavy);
    expect(weatherCondition(86), WeatherCondition.snowShowers);
    expect(weatherCondition(95), WeatherCondition.thunderstorm);
    expect(weatherCondition(99), WeatherCondition.thunderstormHail);
  });

  test('icons: clear skies differ by night, rain and snow do not', () {
    expect(weatherIcon(WeatherCondition.clear), Icons.wb_sunny);
    expect(
      weatherIcon(WeatherCondition.clear, day: false),
      Icons.nightlight_round,
    );
    expect(
      weatherIcon(WeatherCondition.partlyCloudy, day: false),
      Icons.nights_stay,
    );
    expect(weatherIcon(WeatherCondition.rain), Icons.umbrella);
    expect(weatherIcon(WeatherCondition.rain, day: false), Icons.umbrella);
    expect(weatherIcon(WeatherCondition.snow), Icons.cloudy_snowing);
    expect(weatherIcon(WeatherCondition.thunderstorm), Icons.thunderstorm);
    expect(weatherIcon(WeatherCondition.fog), Icons.foggy);
  });

  test('every condition has a German and an English label', () async {
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    for (final c in WeatherCondition.values) {
      expect(weatherLabel(de, c), isNotEmpty);
      expect(weatherLabel(en, c), isNotEmpty);
    }
    expect(weatherLabel(de, weatherCondition(3)), 'Bedeckt');
    expect(weatherLabel(en, weatherCondition(3)), 'Overcast');
    expect(weatherLabel(de, weatherCondition(96)), 'Gewitter mit Hagel');
    expect(weatherLabel(en, weatherCondition(71)), 'Light snow');
    // distinct labels, so no two conditions read the same
    expect(
      WeatherCondition.values.map((c) => weatherLabel(de, c)).toSet().length,
      WeatherCondition.values.length,
    );
  });
}
