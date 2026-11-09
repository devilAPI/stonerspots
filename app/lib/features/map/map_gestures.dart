import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import 'buildings/map_tilt.dart';

/// The main map was left in 3D: it opens tilted next time. Off by default.
final map3dProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('map_3d'),
);

/// The map's tilt in degrees: 0 is the flat 2D map, up to [kMaxPitch].
/// Two fingers change it continuously; the 3D button animates it.
final mapPitchProvider = NotifierProvider<MapPitch, double>(MapPitch.new);

class MapPitch extends Notifier<double> {
  @override
  double build() => ref.read(map3dProvider) ? kMapPitch : 0;

  void set(double degrees) => state = degrees.clamp(0.0, kMaxPitch);
}

/// Degrees of tilt per pixel of a two-finger drag.
const double _tiltPerPixel = 0.25;

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
    final before = _touches[e.pointer];
    _touches[e.pointer] = e.localPosition;
    if (_touches.length != 2 || before == null) return;
    final other = _touches.entries.firstWhere((t) => t.key != e.pointer);
    // both fingers moving up or down together, about as far apart as
    // before: a tilt (a pinch or a twist is flutter_map's)
    final d = e.localPosition - before;
    if (d.dy.abs() < 0.5 || d.dy.abs() < d.dx.abs() * 1.5) return;
    final apartBefore = (other.value - before).distance;
    final apartNow = (other.value - e.localPosition).distance;
    if ((apartNow - apartBefore).abs() > d.dy.abs() * 0.6) return;
    // each finger reports its own move: half of the joint movement each
    _tiltBy(d.dy / 2);
  }

  void _onUp(PointerEvent e) {
    _touches.remove(e.pointer);
    if (_touches.length < 2) _endTilt();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onSignal,
    onPointerPanZoomUpdate: _onPanZoom,
    onPointerPanZoomEnd: (_) => _endTilt(),
    onPointerDown: (e) {
      if (e.kind == PointerDeviceKind.touch) {
        _touches[e.pointer] = e.localPosition;
      }
    },
    onPointerMove: _onMove,
    onPointerUp: _onUp,
    onPointerCancel: _onUp,
    child: widget.child,
  );
}
