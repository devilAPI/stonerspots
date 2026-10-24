import 'dart:async';

import 'package:app/core/api_client.dart';
import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/features/spots/add_spot_controller.dart';
import 'package:app/features/spots/add_spot_screen.dart';
import 'package:app/features/spots/geocode_repository.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _NoLocation implements LocationService {
  @override
  Future<LatLng?> currentPosition() async => null;
}

class _Api implements SpotApi {
  @override
  Future<Spot> setTags(int id, List<SpotTag> tags) =>
      throw UnimplementedError();
  @override
  Future<Spot> getSpot(int id) => throw UnimplementedError();
  @override
  Future<Spot> createSpot(SpotDraft d, {bool force = false}) =>
      throw UnimplementedError();
  @override
  Future<LikeResult> setLike(int spotId, {required bool liked}) =>
      throw UnimplementedError();
  @override
  Future<void> report(String t, int id, String r) async {}
}

class FakeGeo implements GeocodeRepository {
  final queries = <String>[];
  final pending = <Completer<List<GeoResult>>>[];
  Object? error;
  List<GeoResult> results = const [];
  bool manual = false;

  @override
  Future<List<GeoResult>> search(String query) {
    queries.add(query);
    if (manual) {
      final c = Completer<List<GeoResult>>();
      pending.add(c);
      return c.future;
    }
    if (error != null) return Future.error(error!);
    return Future.value(results);
  }
}

const _munich = GeoResult(
  label: 'Marienplatz 1, 80331 München, Bayern, Deutschland',
  lat: 48.1374,
  lon: 11.5755,
);
const _berlin = GeoResult(label: 'Berlin', lat: 52.52, lon: 13.405);

late FakeGeo geo;
late ProviderContainer container;

Future<void> pumpAt(WidgetTester t, Size size) async {
  geo = FakeGeo();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_NoLocation()),
        spotApiProvider.overrideWithValue(_Api()),
        geocodeRepositoryProvider.overrideWithValue(geo),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddSpotScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
  container = ProviderScope.containerOf(t.element(find.byType(AddSpotScreen)));
}

LatLng? get point => container.read(addSpotControllerProvider).point;

Future<void> search(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('placeSearch')), text);
  await t.testTextInput.receiveAction(TextInputAction.search);
  await t.pump();
  await t.pump();
}

void main() {
  for (final size in const [Size(400, 800), Size(1100, 700)]) {
    group('${size.width.toInt()}x${size.height.toInt()}', () {
      testWidgets('coordinates set the point without calling the geocoder', (
        t,
      ) async {
        await pumpAt(t, size);
        await search(t, '48,1234 11,5678');
        await t.pumpAndSettle();
        expect(point!.latitude, closeTo(48.1234, 1e-9));
        expect(point!.longitude, closeTo(11.5678, 1e-9));
        expect(geo.queries, isEmpty);
        expect(t.takeException(), isNull);
      });

      testWidgets('address: results shown, tap sets the point', (t) async {
        await pumpAt(t, size);
        geo.results = const [_munich, _berlin];
        await search(t, 'Marienplatz 1 München');
        await t.pumpAndSettle();
        expect(geo.queries, ['Marienplatz 1 München']);
        expect(find.byKey(const Key('placeResult-0')), findsOneWidget);
        expect(find.byKey(const Key('placeResult-1')), findsOneWidget);
        await t.ensureVisible(find.byKey(const Key('placeResult-0')));
        await t.tap(find.byKey(const Key('placeResult-0')));
        await t.pumpAndSettle();
        expect(point, const LatLng(48.1374, 11.5755));
        expect(find.byKey(const Key('placeResult-0')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('too short query: no call, message', (t) async {
        await pumpAt(t, size);
        await search(t, 'ab');
        await t.pumpAndSettle();
        expect(geo.queries, isEmpty);
        expect(find.text('Please enter at least 3 characters'), findsOne);
      });

      testWidgets('outside region: message, point unchanged', (t) async {
        await pumpAt(t, size);
        await search(t, '40.7128, -74.0060');
        await t.pumpAndSettle();
        expect(point, isNull);
        expect(geo.queries, isEmpty);
        expect(find.textContaining('outside the supported region'), findsOne);
      });

      testWidgets('short link: hint, no call', (t) async {
        await pumpAt(t, size);
        await search(t, 'https://maps.app.goo.gl/xyz');
        await t.pumpAndSettle();
        expect(geo.queries, isEmpty);
        expect(find.textContaining('Short links'), findsOne);
      });

      testWidgets('no result message', (t) async {
        await pumpAt(t, size);
        await search(t, 'Nirgendwo');
        await t.pumpAndSettle();
        expect(find.text('No place found'), findsOne);
      });

      testWidgets('stale response is ignored', (t) async {
        await pumpAt(t, size);
        geo.manual = true;
        await search(t, 'first place');
        await search(t, 'second place');
        expect(geo.pending, hasLength(2));
        geo.pending[1].complete(const [_berlin]);
        await t.pumpAndSettle();
        geo.pending[0].complete(const [_munich]);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('placeResult-0')), findsOneWidget);
        expect(find.text('Berlin'), findsOneWidget);
        expect(find.textContaining('Marienplatz'), findsNothing);
      });

      testWidgets('progress indicator while searching', (t) async {
        await pumpAt(t, size);
        geo.manual = true;
        await search(t, 'some place');
        expect(find.byKey(const Key('placeSearchProgress')), findsOne);
        geo.pending[0].complete(const []);
        await t.pumpAndSettle();
        expect(find.byKey(const Key('placeSearchProgress')), findsNothing);
      });

      final errors = {
        'rate_limited': 'Too many searches',
        'geocoder_unavailable': 'currently unavailable',
        'geocoder_busy': 'currently unavailable',
        'whatever': 'Search failed',
      };
      errors.forEach((code, text) {
        testWidgets('error $code', (t) async {
          await pumpAt(t, size);
          geo.error = ApiException(
            code == 'rate_limited' ? 429 : 502,
            code,
            '',
          );
          await search(t, 'some place');
          await t.pumpAndSettle();
          expect(find.textContaining(text), findsOne);
        });
      });

      testWidgets('clear button empties field and hides results', (t) async {
        await pumpAt(t, size);
        geo.results = const [_munich];
        await search(t, 'Marienplatz');
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('placeSearchClear')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('placeResult-0')), findsNothing);
        expect(
          t
              .widget<TextField>(find.byKey(const Key('placeSearch')))
              .controller!
              .text,
          '',
        );
      });
    });
  }
}
