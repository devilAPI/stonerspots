import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Moves a [MapController] smoothly to another place: centre and zoom glide
/// together, and for a far target the zoom dips on the way so the map shows
/// where it is going instead of racing over tiles.
class MapFlight {
  MapFlight(this.map, TickerProvider vsync)
    : _anim = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 900),
      ) {
    _anim.addListener(_tick);
  }

  final MapController map;
  final AnimationController _anim;
  LatLng _from = const LatLng(0, 0);
  LatLng _to = const LatLng(0, 0);
  double _fromZoom = 0;
  double _toZoom = 0;
  double _dip = 0;

  static const _distance = Distance();

  /// Flies to [centre] at [zoom]; a flight under way is replaced. With
  /// [instant] (reduced motion) it jumps there.
  Future<void> fly(LatLng centre, double zoom, {bool instant = false}) {
    if (instant) {
      stop();
      map.move(centre, zoom, id: 'flight');
      return Future.value();
    }
    final camera = map.camera;
    _from = camera.center;
    _fromZoom = camera.zoom;
    _to = centre;
    _toZoom = zoom;
    // Zoom level at which the whole way roughly fits on the screen.
    final km = _distance.as(LengthUnit.Kilometer, _from, _to);
    final overview = (14 - math.log(math.max(km, 0.5)) / math.ln2).clamp(
      3.0,
      18.0,
    );
    _dip = math.max(0.0, math.min(_fromZoom, _toZoom) - overview);
    return _anim.forward(from: 0).orCancel.catchError((_) {});
  }

  /// Stops where it is, e.g. when the user grabs the map.
  void stop() {
    if (_anim.isAnimating) _anim.stop();
  }

  bool get flying => _anim.isAnimating;

  void _tick() {
    final t = Curves.easeInOutCubic.transform(_anim.value);
    final lat = _from.latitude + (_to.latitude - _from.latitude) * t;
    final lon = _from.longitude + (_to.longitude - _from.longitude) * t;
    final zoom =
        _fromZoom + (_toZoom - _fromZoom) * t - _dip * math.sin(math.pi * t);
    map.move(LatLng(lat, lon), zoom, id: 'flight');
  }

  void dispose() => _anim.dispose();
}
