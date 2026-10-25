import 'package:app/features/spots/location_picker.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('the add-spot map switches between map and satellite', (
    t,
  ) async {
    LatLng? picked;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LocationPicker(point: null, onChanged: (p) => picked = p),
        ),
      ),
    );
    await t.pumpAndSettle();
    String url() => t.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;
    expect(url(), isNot(contains('World_Imagery')));

    await t.tap(find.byKey(const Key('pickerMapLayer')));
    await t.pumpAndSettle();
    expect(url(), contains('World_Imagery'));
    expect(find.text('Esri World Imagery'), findsOneWidget);

    // tapping the map still places the pin
    await t.tapAt(t.getCenter(find.byType(FlutterMap)));
    await t.pump(const Duration(milliseconds: 500)); // double-tap timeout
    expect(picked, isNotNull);

    await t.tap(find.byKey(const Key('pickerMapLayer')));
    await t.pumpAndSettle();
    expect(url(), isNot(contains('World_Imagery')));
  });
}
