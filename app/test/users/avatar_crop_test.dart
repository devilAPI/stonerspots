import 'dart:ui' as ui;

import 'package:app/features/users/avatar_crop.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A [w]×[h] image: left half red, right half blue.
Future<ui.Image> _image(int w, int h) async {
  final r = ui.PictureRecorder();
  Canvas(r)
    ..drawRect(
      Rect.fromLTWH(0, 0, w / 2, h.toDouble()),
      Paint()..color = const Color(0xFFFF0000),
    )
    ..drawRect(
      Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()),
      Paint()..color = const Color(0xFF0000FF),
    );
  final p = r.endRecording();
  final i = await p.toImage(w, h);
  p.dispose();
  return i;
}

void main() {
  group('AvatarCropState', () {
    const photo = Size(4000, 3000);

    test('starts centred on the whole short side', () {
      final s = AvatarCropState(photo);
      expect(s.crop, const Rect.fromLTWH(500, 0, 3000, 3000));
    });

    test('dragging moves the photo, and the circle stays on it', () {
      var s = AvatarCropState(photo);
      // circle 300 px: 10 image px per screen px; drag the photo right
      s = s.panned(const Offset(20, 0), 300);
      expect(s.crop.left, 300);
      s = s.panned(const Offset(1000, 1000), 300);
      expect(s.crop.left, 0);
      expect(s.crop.top, 0);
      s = s.panned(const Offset(-5000, -5000), 300);
      expect(s.crop.right, 4000);
      expect(s.crop.bottom, 3000);
    });

    test('zooming keeps the point under the fingers', () {
      final s = AvatarCropState(photo);
      const focal = Offset(75, 150); // left middle of a 300 px circle
      final before = (focal - s.origin(300)) / s.scale(300);
      final z = s.zoomed(2, focal, 300);
      expect(z.zoom, 2);
      expect(z.side, 1500);
      final after = (focal - z.origin(300)) / z.scale(300);
      expect((after - before).distance, lessThan(1e-6));
      expect(s.zoomed(99, focal, 300).zoom, kAvatarMaxZoom);
      expect(s.zoomed(0.1, focal, 300).zoom, 1);
    });
  });

  testWidgets('renders the chosen square as a small JPEG', (t) async {
    await t.runAsync(() async {
      final image = await _image(2000, 1000);
      // the right, blue half only
      final jpeg = await renderAvatarCrop(
        image,
        const Rect.fromLTWH(1000, 0, 1000, 1000),
      );
      image.dispose();
      final out = img.decodeJpg(jpeg)!;
      expect(out.width, kAvatarCropSize);
      expect(out.height, kAvatarCropSize);
      final px = out.getPixel(320, 320);
      expect(px.b, greaterThan(200));
      expect(px.r, lessThan(60));
    });
  });

  testWidgets('the crop screen hands back the square that was chosen', (
    t,
  ) async {
    t.view.physicalSize = const Size(400, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final image = (await t.runAsync(() => _image(1200, 600)))!;
    addTearDown(image.dispose);
    Rect? result;
    await t.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.push<Rect>(
                context,
                MaterialPageRoute(
                  builder: (_) => AvatarCropScreen(image: image),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Crop picture'), findsOneWidget);
    // drag the photo to the left: the circle moves right, as far as it goes
    await t.drag(
      find.byKey(const Key('avatarCropArea')),
      const Offset(-600, 0),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('avatarCropDone')));
    await t.pumpAndSettle();
    expect(result, const Rect.fromLTWH(600, 0, 600, 600));
  });
}
