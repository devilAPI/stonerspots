import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';

/// Side of a cropped profile picture in pixels (less when the chosen part
/// of the photo is smaller).
const int kAvatarCropSize = 640;

/// How far into a photo the crop can zoom (1 = its short side fills the
/// circle).
const double kAvatarMaxZoom = 5;

/// Lets the user cut the square part of [file] that becomes the profile
/// picture; null when cancelled. A photo that cannot be shown is returned
/// as it is (the server checks it).
typedef AvatarCropper = Future<XFile?> Function(
  BuildContext context,
  XFile file,
);

final avatarCropperProvider = Provider<AvatarCropper>((ref) => cropAvatar);

Future<XFile?> cropAvatar(BuildContext context, XFile file) async {
  final bytes = await file.readAsBytes();
  final ui.Image image;
  try {
    // the engine applies the EXIF orientation: what is shown is cut
    image = await decodeImageFromList(bytes);
  } catch (_) {
    return file;
  }
  if (!context.mounted) {
    image.dispose();
    return null;
  }
  final crop = await Navigator.of(context, rootNavigator: true).push<Rect>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => AvatarCropScreen(image: image),
    ),
  );
  try {
    if (crop == null) return null;
    final jpeg = await renderAvatarCrop(image, crop);
    return XFile.fromData(jpeg, name: 'avatar.jpg', mimeType: 'image/jpeg');
  } finally {
    image.dispose();
  }
}

/// Cuts [crop] (image pixels) out of [image] as a square JPEG of at most
/// [kAvatarCropSize] pixels, without metadata. Transparency becomes white.
Future<Uint8List> renderAvatarCrop(ui.Image image, Rect crop) async {
  final side = math.max(1, math.min(kAvatarCropSize, crop.width.round()));
  final dst = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..drawRect(dst, Paint()..color = Colors.white)
    ..drawImageRect(
      image,
      crop,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
  final picture = recorder.endRecording();
  final out = await picture.toImage(side, side);
  picture.dispose();
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  out.dispose();
  final rgba = img.Image.fromBytes(
    width: side,
    height: side,
    bytes: data!.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(rgba, quality: 90);
}

/// Where the crop circle sits on a photo: its [center] in image pixels and
/// the [zoom]. At zoom 1 the photo's short side fills the circle; the
/// circle never leaves the photo.
@immutable
class AvatarCropState {
  AvatarCropState(this.image, {Offset? center, double zoom = 1})
    : zoom = zoom.clamp(1.0, kAvatarMaxZoom),
      center = _clampCenter(
        image,
        center ?? image.center(Offset.zero),
        math.min(image.width, image.height) / zoom.clamp(1.0, kAvatarMaxZoom),
      );

  final Size image;
  final Offset center;
  final double zoom;

  /// The part of the photo inside the circle, in image pixels.
  double get side => math.min(image.width, image.height) / zoom;
  Rect get crop => Rect.fromCenter(center: center, width: side, height: side);

  /// Screen pixels per image pixel for a circle [view] pixels across.
  double scale(double view) => view / side;

  /// Where the photo's top left corner is drawn, from the circle's.
  Offset origin(double view) =>
      Offset(view / 2, view / 2) - center * scale(view);

  /// Moved by a drag of [delta] screen pixels.
  AvatarCropState panned(Offset delta, double view) =>
      AvatarCropState(image, center: center - delta / scale(view), zoom: zoom);

  /// Zoomed to [to], keeping the photo point under [focal] (screen pixels
  /// from the circle's top left) where it is.
  AvatarCropState zoomed(double to, Offset focal, double view) {
    final next = to.clamp(1.0, kAvatarMaxZoom);
    final point = (focal - origin(view)) / scale(view);
    final nextScale = view / (math.min(image.width, image.height) / next);
    final c = point - (focal - Offset(view / 2, view / 2)) / nextScale;
    return AvatarCropState(image, center: c, zoom: next);
  }

  static Offset _clampCenter(Size image, Offset c, double side) => Offset(
    c.dx.clamp(side / 2, image.width - side / 2),
    c.dy.clamp(side / 2, image.height - side / 2),
  );
}

/// Full-screen cropper: drag to move, pinch, scroll or the slider to zoom.
/// Pops with the chosen square in image pixels.
class AvatarCropScreen extends StatefulWidget {
  const AvatarCropScreen({super.key, required this.image});

  final ui.Image image;

  @override
  State<AvatarCropScreen> createState() => _AvatarCropScreenState();
}

class _AvatarCropScreenState extends State<AvatarCropScreen> {
  late AvatarCropState _state = AvatarCropState(
    Size(widget.image.width.toDouble(), widget.image.height.toDouble()),
  );
  double _startZoom = 1;
  Offset _lastFocal = Offset.zero;

  /// The circle's side and top left on screen; set by the layout.
  double _view = 1;
  Offset _circle = Offset.zero;

  Offset _inCircle(Offset local) => local - _circle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l.avatarCropTitle),
        actions: [
          TextButton(
            key: const Key('avatarCropDone'),
            onPressed: () => Navigator.pop(context, _state.crop),
            child: Text(l.avatarCropUse),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  _view = math.max(
                    1,
                    math.min(box.maxWidth, box.maxHeight) - 32,
                  );
                  _circle = Offset(
                    (box.maxWidth - _view) / 2,
                    (box.maxHeight - _view) / 2,
                  );
                  final scale = _state.scale(_view);
                  final at = _circle + _state.origin(_view);
                  return Listener(
                    onPointerSignal: (e) {
                      if (e is PointerScrollEvent) {
                        final factor = math.pow(2, -e.scrollDelta.dy / 300);
                        setState(() {
                          _state = _state.zoomed(
                            _state.zoom * factor,
                            _inCircle(e.localPosition),
                            _view,
                          );
                        });
                      }
                    },
                    child: GestureDetector(
                      key: const Key('avatarCropArea'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (d) {
                        _startZoom = _state.zoom;
                        _lastFocal = d.localFocalPoint;
                      },
                      onScaleUpdate: (d) => setState(() {
                        var s = _state.panned(
                          d.localFocalPoint - _lastFocal,
                          _view,
                        );
                        if (d.pointerCount > 1) {
                          s = s.zoomed(
                            _startZoom * d.scale,
                            _inCircle(d.localFocalPoint),
                            _view,
                          );
                        }
                        _state = s;
                        _lastFocal = d.localFocalPoint;
                      }),
                      child: Stack(
                        children: [
                          Positioned(
                            left: at.dx,
                            top: at.dy,
                            width: widget.image.width * scale,
                            height: widget.image.height * scale,
                            child: RawImage(
                              image: widget.image,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CircleMask(
                                Rect.fromLTWH(
                                  _circle.dx,
                                  _circle.dy,
                                  _view,
                                  _view,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out, color: Colors.white70),
                  Expanded(
                    child: Slider(
                      key: const Key('avatarCropZoom'),
                      label: l.avatarCropZoom,
                      min: 1,
                      max: kAvatarMaxZoom,
                      value: _state.zoom,
                      onChanged: (z) => setState(() {
                        _state = _state.zoomed(
                          z,
                          Offset(_view / 2, _view / 2),
                          _view,
                        );
                      }),
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white70),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything but the circle and outlines it.
class _CircleMask extends CustomPainter {
  _CircleMask(this.circle);

  final Rect circle;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_CircleMask old) => old.circle != circle;
}
