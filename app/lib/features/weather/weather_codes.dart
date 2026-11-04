import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What a WMO weather interpretation code (as sent by Open-Meteo) describes.
enum WeatherCondition {
  clear,
  mainlyClear,
  partlyCloudy,
  overcast,
  fog,
  drizzle,
  freezingDrizzle,
  rainLight,
  rain,
  rainHeavy,
  freezingRain,
  snowLight,
  snow,
  snowHeavy,
  snowGrains,
  showers,
  showersHeavy,
  snowShowers,
  thunderstorm,
  thunderstormHail,
  unknown,
}

/// Maps a WMO code (0-99, see https://open-meteo.com/en/docs) to a
/// condition; codes Open-Meteo does not use come out as unknown.
WeatherCondition weatherCondition(int? code) => switch (code) {
  0 => WeatherCondition.clear,
  1 => WeatherCondition.mainlyClear,
  2 => WeatherCondition.partlyCloudy,
  3 => WeatherCondition.overcast,
  45 || 48 => WeatherCondition.fog,
  51 || 53 || 55 => WeatherCondition.drizzle,
  56 || 57 => WeatherCondition.freezingDrizzle,
  61 => WeatherCondition.rainLight,
  63 => WeatherCondition.rain,
  65 => WeatherCondition.rainHeavy,
  66 || 67 => WeatherCondition.freezingRain,
  71 => WeatherCondition.snowLight,
  73 => WeatherCondition.snow,
  75 => WeatherCondition.snowHeavy,
  77 => WeatherCondition.snowGrains,
  80 || 81 => WeatherCondition.showers,
  82 => WeatherCondition.showersHeavy,
  85 || 86 => WeatherCondition.snowShowers,
  95 => WeatherCondition.thunderstorm,
  96 || 99 => WeatherCondition.thunderstormHail,
  _ => WeatherCondition.unknown,
};

/// The icon for [c]; clear and lightly clouded skies differ by night.
IconData weatherIcon(WeatherCondition c, {bool day = true}) => switch (c) {
  WeatherCondition.clear => day ? Icons.wb_sunny : Icons.nightlight_round,
  WeatherCondition.mainlyClear || WeatherCondition.partlyCloudy =>
    day ? Icons.wb_cloudy_outlined : Icons.nights_stay,
  WeatherCondition.overcast => Icons.cloud,
  WeatherCondition.fog => Icons.foggy,
  WeatherCondition.drizzle || WeatherCondition.rainLight => Icons.grain,
  WeatherCondition.rain ||
  WeatherCondition.rainHeavy ||
  WeatherCondition.showers ||
  WeatherCondition.showersHeavy => Icons.umbrella,
  WeatherCondition.freezingDrizzle ||
  WeatherCondition.freezingRain => Icons.ac_unit,
  WeatherCondition.snowLight ||
  WeatherCondition.snow ||
  WeatherCondition.snowHeavy ||
  WeatherCondition.snowGrains ||
  WeatherCondition.snowShowers => Icons.cloudy_snowing,
  WeatherCondition.thunderstorm ||
  WeatherCondition.thunderstormHail => Icons.thunderstorm,
  WeatherCondition.unknown => Icons.device_thermostat,
};

String weatherLabel(AppLocalizations l, WeatherCondition c) => switch (c) {
  WeatherCondition.clear => l.weatherClear,
  WeatherCondition.mainlyClear => l.weatherMainlyClear,
  WeatherCondition.partlyCloudy => l.weatherPartlyCloudy,
  WeatherCondition.overcast => l.weatherOvercast,
  WeatherCondition.fog => l.weatherFog,
  WeatherCondition.drizzle => l.weatherDrizzle,
  WeatherCondition.freezingDrizzle => l.weatherFreezingDrizzle,
  WeatherCondition.rainLight => l.weatherRainLight,
  WeatherCondition.rain => l.weatherRain,
  WeatherCondition.rainHeavy => l.weatherRainHeavy,
  WeatherCondition.freezingRain => l.weatherFreezingRain,
  WeatherCondition.snowLight => l.weatherSnowLight,
  WeatherCondition.snow => l.weatherSnow,
  WeatherCondition.snowHeavy => l.weatherSnowHeavy,
  WeatherCondition.snowGrains => l.weatherSnowGrains,
  WeatherCondition.showers => l.weatherShowers,
  WeatherCondition.showersHeavy => l.weatherShowersHeavy,
  WeatherCondition.snowShowers => l.weatherSnowShowers,
  WeatherCondition.thunderstorm => l.weatherThunderstorm,
  WeatherCondition.thunderstormHail => l.weatherThunderstormHail,
  WeatherCondition.unknown => l.weatherUnknown,
};
