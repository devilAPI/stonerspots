import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/spots/spot_media.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(
  WidgetTester t,
  List<String> urls, {
  void Function(int)? onTap,
}) => t.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SpotMediaStrip(
        photoUrls: urls,
        lat: 48.1,
        lon: 11.6,
        height: 150,
        onPhotoTap: onTap,
      ),
    ),
  ),
);

void main() {
  testWidgets('user photos come first, the top-down view last', (t) async {
    await pump(t, ['http://h/a.jpg', 'http://h/b.jpg']);
    final a = t.getTopLeft(find.byKey(const Key('galleryPhoto_0'))).dx;
    final b = t.getTopLeft(find.byKey(const Key('galleryPhoto_1'))).dx;
    final sat = t.getTopLeft(find.byType(SatelliteThumb)).dx;
    expect(a, lessThan(b));
    expect(b, lessThan(sat));
    expect(find.byType(CachedNetworkImage), findsNWidgets(2));
  });

  testWidgets('without photos only the top-down view is shown', (t) async {
    await pump(t, const []);
    expect(find.byType(SatelliteThumb), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('empty or host-less urls are ignored instead of crashing', (
    t,
  ) async {
    await pump(t, ['', '   ', '/relative/a.jpg', 'http://h/ok.jpg']);
    expect(t.takeException(), isNull);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.byType(SatelliteThumb), findsOneWidget);
  });

  testWidgets('tapping a photo reports its index among the valid photos', (
    t,
  ) async {
    int? tapped;
    await pump(t, [
      '',
      'http://h/a.jpg',
      'http://h/b.jpg',
    ], onTap: (i) => tapped = i);
    await t.tap(find.byKey(const Key('galleryPhoto_1')));
    expect(tapped, 1);
  });
}
