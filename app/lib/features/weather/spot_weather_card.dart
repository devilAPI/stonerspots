import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import 'weather_codes.dart';
import 'weather_repository.dart';

/// Current weather and the next hours at a spot. Shows nothing while
/// loading or when the weather service fails: it is a nice extra, not
/// something the page needs.
class SpotWeatherCard extends ConsumerWidget {
  const SpotWeatherCard({
    super.key,
    required this.spotId,
    required this.lat,
    required this.lon,
    this.padding = EdgeInsets.zero,
    this.title,
    this.dividerAbove = false,
  });

  final int spotId;
  final double lat;
  final double lon;

  /// Around the card (and [title]) when it is shown.
  final EdgeInsetsGeometry padding;

  /// A section heading above the card, hidden with it.
  final String? title;

  /// A divider above it all, hidden with it, for a section of a page.
  final bool dividerAbove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref
        .watch(spotWeatherProvider((spotId: spotId, lat: lat, lon: lon)))
        .value;
    if (weather == null) return const SizedBox.shrink();
    final title = this.title;
    final Widget content = Padding(
      padding: padding,
      child: title == null
          ? _WeatherCard(weather: weather)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const Key('weatherHeading'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _WeatherCard(weather: weather),
              ],
            ),
    );
    if (!dividerAbove) return content;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const Divider(), content],
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.weather});

  final SpotWeather weather;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final condition = weatherCondition(weather.code);
    final muted = theme.colorScheme.onSurfaceVariant;
    final details = [
      l.weatherWind(weather.windKmh.round().toString()),
      if (weather.precipitationChance != null)
        l.weatherRainChance(weather.precipitationChance!),
      if (weather.precipitationMm > 0)
        l.weatherPrecipitation(
          NumberFormat('0.#', locale).format(weather.precipitationMm),
        ),
    ].join(' · ');

    return Card.outlined(
      key: const Key('spotWeather'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  weatherIcon(condition, day: weather.isDay),
                  key: const Key('weatherIcon'),
                  size: 36,
                ),
                const SizedBox(width: 12),
                Text(
                  _degrees(weather.temperature),
                  key: const Key('weatherTemp'),
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        weatherLabel(l, condition),
                        key: const Key('weatherLabel'),
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        details,
                        key: const Key('weatherDetails'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (weather.hours.isNotEmpty) ...[
              const SizedBox(height: 10),
              Semantics(
                label: l.weatherNextHours,
                child: Row(
                  children: [
                    for (final h in weather.hours)
                      Expanded(
                        child: _Hour(hour: h, locale: locale),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              l.weatherAttribution,
              key: const Key('weatherAttribution'),
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hour extends StatelessWidget {
  const _Hour({required this.hour, required this.locale});

  final HourlyWeather hour;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final chance = hour.precipitationChance;
    final condition = weatherCondition(hour.code);
    return Tooltip(
      message: weatherLabel(AppLocalizations.of(context), condition),
      child: Column(
        children: [
          Text(
            DateFormat.j(locale).format(hour.time),
            style: small,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
          ),
          const SizedBox(height: 2),
          Icon(weatherIcon(condition, day: hour.isDay), size: 20),
          const SizedBox(height: 2),
          Text(_degrees(hour.temperature), style: theme.textTheme.labelLarge),
          Text(
            chance != null && chance > 0
                ? NumberFormat.percentPattern(locale).format(chance / 100)
                : '',
            style: small,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// `8°`, `-3°`: whole degrees, no unit (Celsius is the only one used here).
String _degrees(double t) => '${t.round()}°';
