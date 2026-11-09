import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'buildings/map_tilt.dart';

/// The 3D tilt in degrees (this session); two fingers change it.
final mapPitchProvider = NotifierProvider<MapPitch, double>(MapPitch.new);

class MapPitch extends Notifier<double> {
  @override
  double build() => kMapPitch;

  void set(double degrees) => state = degrees.clamp(kMinPitch, kMaxPitch);
}

/// Degrees of tilt per pixel of a two-finger drag.
const double _tiltPerPixel = 0.25;

/// flutter_map's own scroll-wheel step (zoom levels per pixel of scroll).
const double _wheelVelocity = 0.005;

/// What flutter_map should handle itself: everything but the scroll wheel
/// (this layer zooms with a mouse wheel and moves with a touchpad), and in
/// 3D not moving with two fingers either (that tilts there).
int mapInteractionFlags({required bool tilted}) {
  var flags = InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom;
  if (tilted) flags &= ~InteractiveFlag.pinchMove;
  return flags;
}

/// Gestures around the map, on top of flutter_map's own:
///
/// - mouse wheel: zooms towards the cursor (as flutter_map does);
/// - touchpad, two fingers: moves the map (scroll events or pan/zoom
///   gestures, whichever the platform sends); in 3D with Shift held, an
///   up/down swipe tilts instead;
/// - touchscreen in 3D: two fingers dragged up or down tilt the map.
///
/// Three-finger touchpad gestures are kept by the operating systems
/// (workspace switching) and never reach apps, hence Shift.
class MapGestures extends ConsumerStatefulWidget {
  const MapGestures({
    super.key,
    required this.controller,
    required this.tilted,
    required this.child,
  });

  final MapController controller;
  final bool tilted;
  final Widget child;

  @override
  ConsumerState<MapGestures> createState() => _MapGesturesState();
}

class _MapGesturesState extends ConsumerState<MapGestures> {
  /// Touch pointers down: their last position.
  final _touches = <int, Offset>{};

  MapTilt? _tilt() {
    if (!widget.tilted) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return MapTilt(screen: box.size, pitchDegrees: ref.read(mapPitchProvider));
  }

  /// Screen point to map-local point (through the tilt in 3D).
  Offset _toMap(Offset screen, MapTilt? tilt) =>
      tilt == null ? screen : tilt.toMap(screen);

  /// Moves the map so that the ground under screen point [from] comes to
  /// lie under [to].
  void _pan(Offset from, Offset to) {
    final camera = widget.controller.camera;
    final tilt = _tilt();
    // map-local points (the tilted map is larger than the screen; toMap
    // already answers in its own coordinates)
    final a = tilt == null ? from : tilt.toMap(from);
    final b = tilt == null ? to : tilt.toMap(to);
    final centre = camera.nonRotatedSize.center(Offset.zero);
    final target = camera.screenOffsetToLatLng(centre + (a - b));
    widget.controller.move(target, camera.zoom);
  }

  void _tiltBy(double dy) {
    final p = ref.read(mapPitchProvider.notifier);
    // fingers up: lean further back (like the big map apps)
    p.set(ref.read(mapPitchProvider) - dy * _tiltPerPixel);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (s.kind == PointerDeviceKind.trackpad && !ctrl) {
        if (widget.tilted && HardwareKeyboard.instance.isShiftPressed) {
          _tiltBy(-s.scrollDelta.dy);
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
    // 2D: flutter_map moves and zooms with these itself
    if (!widget.tilted) return;
    final delta = e.localPanDelta;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _tiltBy(delta.dy);
      return;
    }
    // in 3D flutter_map does not move with two fingers (they tilt on a
    // touchscreen), so a touchpad swipe is moved here
    if ((e.scale - 1).abs() < 0.02) {
      _pan(e.localPosition - delta, e.localPosition);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    final before = _touches[e.pointer];
    _touches[e.pointer] = e.localPosition;
    if (!widget.tilted || _touches.length != 2 || before == null) return;
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

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onSignal,
    onPointerPanZoomUpdate: _onPanZoom,
    onPointerDown: (e) {
      if (e.kind == PointerDeviceKind.touch) {
        _touches[e.pointer] = e.localPosition;
      }
    },
    onPointerMove: _onMove,
    onPointerUp: (e) => _touches.remove(e.pointer),
    onPointerCancel: (e) => _touches.remove(e.pointer),
    child: widget.child,
  );
}
