import 'package:app/features/weather/spot_weather_card.dart';
import 'package:app/features/weather/weather_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'weather_helpers.dart';

Future<void> _pump(
  WidgetTester t,
  FakeWeather repo, {
  String lang = 'en',
  String? title,
}) => t.pumpWidget(
  ProviderScope(
    overrides: [weatherRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: SpotWeatherCard(
            spotId: 3,
            lat: 52.52,
            lon: 13.4,
            title: title,
            dividerAbove: title != null,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows now, the next hours and the source', (t) async {
    final repo = FakeWeather();
    await _pump(t, repo);
    await t.pumpAndSettle();

    expect(repo.asked.single, (spotId: 3, lat: 52.52, lon: 13.4));
    expect(find.byKey(const Key('spotWeather')), findsOneWidget);
    expect(find.text('8°'), findsWidgets);
    expect(find.text('Light rain'), findsOneWidget);
    expect(find.text('Wind 15 km/h · Rain 70% · 0.3 mm'), findsOneWidget);
    expect(find.text('Weather: Open-Meteo.com'), findsOneWidget);
    expect(
      t.widget<Icon>(find.byKey(const Key('weatherIcon'))).icon,
      Icons.grain,
    );
    // five hours with data after 14:00, from 3 PM on
    // intl may put a narrow no-break space before "PM"
    expect(find.textContaining(RegExp(r'^3\sPM$')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^7\sPM$')), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('German labels and units', (t) async {
    await _pump(t, FakeWeather(), lang: 'de');
    await t.pumpAndSettle();
    expect(find.text('Leichter Regen'), findsOneWidget);
    expect(find.text('Wind 15 km/h · Regen 70 % · 0,3 mm'), findsOneWidget);
    expect(find.text('Wetter: Open-Meteo.com'), findsOneWidget);
    expect(find.text('15 Uhr'), findsOneWidget);
  });

  testWidgets('a failing weather service hides the card', (t) async {
    await _pump(t, FakeWeather(error: Exception('offline')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('spotWeather')), findsNothing);
    expect(find.textContaining('Open-Meteo'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('nothing shows while loading', (t) async {
    await _pump(t, FakeWeather());
    expect(find.byKey(const Key('spotWeather')), findsNothing);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('spotWeather')), findsOneWidget);
  });

  testWidgets('a section heading and divider show with the card', (t) async {
    await _pump(t, FakeWeather(), title: 'Weather');
    // loading: neither heading nor divider
    expect(find.byKey(const Key('weatherHeading')), findsNothing);
    expect(find.byType(Divider), findsNothing);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('weatherHeading')), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    // the heading sits above the card
    expect(
      t.getTopLeft(find.byKey(const Key('weatherHeading'))).dy,
      lessThan(t.getTopLeft(find.byKey(const Key('spotWeather'))).dy),
    );
  });

  testWidgets('the heading hides with the card when the service fails', (
    t,
  ) async {
    await _pump(t, FakeWeather(error: Exception('offline')), title: 'Weather');
    await t.pumpAndSettle();
    expect(find.byKey(const Key('weatherHeading')), findsNothing);
    expect(find.text('Weather'), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });
}
