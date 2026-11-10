import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'buildings/map_tilt.dart';

/// The map's tilt in degrees: 0 is the flat 2D map, up to [kMaxPitch].
/// Two fingers change it continuously; the 3D button animates it. The map
/// always opens flat; 3D is a choice for the moment, not remembered.
final mapPitchProvider = NotifierProvider<MapPitch, double>(MapPitch.new);

class MapPitch extends Notifier<double> {
  @override
  double build() => 0;

  void set(double degrees) => state = degrees.clamp(0.0, kMaxPitch);
}

/// Degrees of tilt per pixel of a two-finger drag.
const double _tiltPerPixel = 0.25;

/// A two-finger gesture is a tilt once both fingers moved this far up or
/// down together; it is a twist or a pinch (flutter_map's, never a tilt)
/// once the line between them turned this much or their distance changed
/// by this share - whichever comes first.
const double _decideTiltPixels = 20;
const double _decideTwistDegrees = 10;
const double _decidePinch = 0.12;

enum _TwoFingers { tilt, other }

/// flutter_map's own scroll-wheel step (zoom levels per pixel of scroll).
const double _wheelVelocity = 0.005;

/// A Shift + touchpad tilt sent as scroll events has no end event: it ends
/// after this pause.
const Duration _scrollTiltEnd = Duration(milliseconds: 250);

/// What flutter_map handles itself: everything but the scroll wheel (this
/// layer zooms with a mouse wheel and moves with a touchpad) and moving with
/// two fingers (two fingers dragged up or down tilt, as in the big map
/// apps; a pinch still zooms and a twist still turns).
int mapInteractionFlags({bool tilting = false}) {
  var flags =
      InteractiveFlag.all &
      ~InteractiveFlag.scrollWheelZoom &
      ~InteractiveFlag.pinchMove;
  // during a two-finger tilt the fingers seem to pinch and turn on the
  // tilting ground: no zoom or twist then
  if (tilting) {
    flags &= ~InteractiveFlag.pinchZoom & ~InteractiveFlag.rotate;
  }
  return flags;
}

/// Gestures around the map, on top of flutter_map's own:
///
/// - mouse wheel: zooms towards the cursor (as flutter_map does);
/// - touchpad, two fingers: moves the map (scroll events or pan/zoom
///   gestures, whichever the platform sends); with Shift held, an up/down
///   swipe tilts instead;
/// - touchscreen: two fingers dragged up or down tilt the map, from flat
///   2D into 3D and back.
///
/// [onTiltStart] and [onTiltEnd] bracket a tilt: meanwhile the map page
/// pauses flutter_map's pinch zoom and twist (seen through the changing
/// tilt, two still fingers would seem to pinch and turn), and afterwards
/// lets a nearly flat map settle to 2D. Three-finger touchpad gestures are kept by the
/// operating systems (workspace switching) and never reach apps, hence
/// Shift.
class MapGestures extends ConsumerStatefulWidget {
  const MapGestures({
    super.key,
    required this.controller,
    required this.onTiltStart,
    required this.onTiltEnd,
    required this.child,
  });

  final MapController controller;
  final VoidCallback onTiltStart;
  final VoidCallback onTiltEnd;
  final Widget child;

  @override
  ConsumerState<MapGestures> createState() => _MapGesturesState();
}

class _MapGesturesState extends ConsumerState<MapGestures> {
  /// Touch pointers down: their last position.
  final _touches = <int, Offset>{};

  /// Where the two fingers of the current two-finger gesture started, and
  /// what the gesture turned out to be (null: not decided yet).
  final _starts = <int, Offset>{};
  _TwoFingers? _kind;

  /// The joint vertical movement already turned into tilt.
  double _tiltedDy = 0;

  /// The camera when the second finger came down: a tilt keeps the map
  /// exactly there (flutter_map may have reacted to the first, undecided
  /// pixels as a tiny pinch or twist).
  MapCamera? _cameraAtStart;

  /// A tilt is going on (ends with the fingers, the pan gesture or a
  /// pause in Shift-scrolling).
  bool _tilting = false;
  Timer? _scrollTiltTimer;

  @override
  void dispose() {
    _scrollTiltTimer?.cancel();
    super.dispose();
  }

  MapTilt? _tilt() {
    final pitch = ref.read(mapPitchProvider);
    if (pitch <= 0) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return MapTilt(screen: box.size, pitchDegrees: pitch);
  }

  /// Screen point to map-local point (through the tilt in 3D).
  Offset _toMap(Offset screen, MapTilt? tilt) =>
      tilt == null ? screen : tilt.toMap(screen);

  /// Moves the map so that the ground under screen point [from] comes to
  /// lie under [to].
  void _pan(Offset from, Offset to) {
    final camera = widget.controller.camera;
    final tilt = _tilt();
    final a = _toMap(from, tilt), b = _toMap(to, tilt);
    final centre = camera.nonRotatedSize.center(Offset.zero);
    final target = camera.screenOffsetToLatLng(centre + (a - b));
    widget.controller.move(target, camera.zoom);
  }

  void _tiltBy(double dy) {
    if (!_tilting) {
      _tilting = true;
      widget.onTiltStart();
    }
    // fingers up: lean further back (like the big map apps)
    ref
        .read(mapPitchProvider.notifier)
        .set(ref.read(mapPitchProvider) - dy * _tiltPerPixel);
  }

  void _endTilt() {
    if (!_tilting) return;
    _tilting = false;
    widget.onTiltEnd();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (s.kind == PointerDeviceKind.trackpad && !ctrl) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          _tiltBy(-s.scrollDelta.dy);
          _scrollTiltTimer?.cancel();
          _scrollTiltTimer = Timer(_scrollTiltEnd, _endTilt);
        } else {
          _pan(s.localPosition, s.localPosition - s.scrollDelta);
        }
        return;
      }
      if (s.scrollDelta.dy == 0) return;
      final camera = widget.controller.camera;
      final zoom = (camera.zoom - s.scrollDelta.dy * _wheelVelocity).clamp(
        camera.minZoom ?? 0.0,
        camera.maxZoom ?? double.infinity,
      );
      final at = _toMap(s.localPosition, _tilt());
      widget.controller.move(camera.focusedZoomCenter(at, zoom), zoom);
    });
  }

  void _onPanZoom(PointerPanZoomUpdateEvent e) {
    final delta = e.localPanDelta;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _tiltBy(delta.dy);
      return;
    }
    // flutter_map does not move with two fingers (on a touchscreen they
    // tilt), so a touchpad swipe is moved here; a pinch is flutter_map's
    if ((e.scale - 1).abs() < 0.02) {
      _pan(e.localPosition - delta, e.localPosition);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    if (!_touches.containsKey(e.pointer)) return;
    _touches[e.pointer] = e.localPosition;
    if (_touches.length != 2 || _starts.length != 2) return;
    final ids = _starts.keys.toList();
    final a0 = _starts[ids[0]]!, b0 = _starts[ids[1]]!;
    final a = _touches[ids[0]]!, b = _touches[ids[1]]!;
    final da = a - a0, db = b - b0;
    if (_kind == null) {
      // a twist or a pinch is flutter_map's: no tilt for this gesture
      final turned = ((b - a).direction - (b0 - a0).direction).abs();
      final twist = math.min(turned, 2 * math.pi - turned) * 180 / math.pi;
      final apart = (b - a).distance / math.max((b0 - a0).distance, 1);
      if (twist > _decideTwistDegrees || (apart - 1).abs() > _decidePinch) {
        _kind = _TwoFingers.other;
        return;
      }
      // both fingers up (or down) together, clearly more than sideways
      final dy = (da.dy + db.dy) / 2, dx = (da.dx + db.dx) / 2;
      final together =
          da.dy.sign == db.dy.sign &&
          da.dy.abs() > da.dx.abs() &&
          db.dy.abs() > db.dx.abs();
      if (!together ||
          dy.abs() < _decideTiltPixels ||
          dy.abs() < 2 * dx.abs()) {
        return;
      }
      _kind = _TwoFingers.tilt;
      _tiltedDy = 0;
    }
    if (_kind != _TwoFingers.tilt) return;
    // the joint movement since the start, the part not applied yet
    final dy = (da.dy + db.dy) / 2;
    _tiltBy(dy - _tiltedDy);
    _tiltedDy = dy;
    final c = _cameraAtStart;
    if (c != null) {
      widget.controller.moveAndRotate(c.center, c.zoom, c.rotation);
    }
  }

  void _onDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    _touches[e.pointer] = e.localPosition;
    _starts.clear();
    _kind = null;
    if (_touches.length == 2) {
      _starts.addAll(_touches);
      _cameraAtStart = widget.controller.camera;
    }
  }

  void _onUp(PointerEvent e) {
    _touches.remove(e.pointer);
    _starts.clear();
    _kind = null;
    if (_touches.length < 2) _endTilt();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onSignal,
    onPointerPanZoomUpdate: _onPanZoom,
    onPointerPanZoomEnd: (_) => _endTilt(),
    onPointerDown: _onDown,
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: widget.child,
  );
}
