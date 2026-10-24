import 'package:app/core/location_service.dart';
import 'package:app/core/models.dart';
import 'package:app/features/spots/add_spot_screen.dart';
import 'package:app/features/spots/location_picker.dart';
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

Future<void> pumpAt(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(_NoLocation()),
        spotApiProvider.overrideWithValue(_Api()),
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
}

void main() {
  testWidgets(
    'wide window: map beside the form, save button visible without scrolling',
    (t) async {
      await pumpAt(t, const Size(1100, 700));
      expect(find.byKey(const Key('addSpotTwoPane')), findsOneWidget);
      expect(find.byType(LocationPicker), findsOneWidget);
      final map = t.getRect(find.byType(LocationPicker));
      final title = t.getRect(find.byKey(const Key('title')));
      expect(
        map.right,
        lessThanOrEqualTo(title.left),
        reason: 'map is left of the form',
      );
      expect(
        t.getRect(find.byKey(const Key('save'))).bottom,
        lessThanOrEqualTo(700),
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('landscape phone: two panes without overflow', (t) async {
    await pumpAt(t, const Size(844, 390));
    expect(find.byKey(const Key('addSpotTwoPane')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('phone portrait: single column', (t) async {
    await pumpAt(t, const Size(400, 800));
    expect(find.byKey(const Key('addSpotTwoPane')), findsNothing);
    expect(find.byType(LocationPicker), findsOneWidget);
    expect(find.byKey(const Key('title')), findsOneWidget);
  });

  testWidgets('tags section offers all seven chips and toggles them', (
    t,
  ) async {
    await pumpAt(t, const Size(1100, 700));
    for (final tag in SpotTag.values) {
      final f = find.byKey(Key('tag-${tag.wire}'));
      await t.ensureVisible(f);
      expect(f, findsOneWidget);
    }
    final roof = find.byKey(const Key('tag-roof'));
    expect(t.widget<FilterChip>(roof).selected, isFalse);
    await t.tap(roof);
    await t.pump();
    expect(t.widget<FilterChip>(roof).selected, isTrue);
    await t.tap(roof);
    await t.pump();
    expect(t.widget<FilterChip>(roof).selected, isFalse);
  });

  testWidgets('tags are reachable in the single column without overflow', (
    t,
  ) async {
    await pumpAt(t, const Size(400, 800));
    await t.scrollUntilVisible(
      find.byKey(const Key('tag-lit')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('tag-lit')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('landscape phone: tags without overflow', (t) async {
    await pumpAt(t, const Size(844, 390));
    await t.ensureVisible(find.byKey(const Key('tag-lit')));
    expect(t.takeException(), isNull);
  });
}
