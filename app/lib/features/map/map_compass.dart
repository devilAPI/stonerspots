import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../l10n/app_localizations.dart';

/// A compass for the map controls: its needle points north as the map turns,
/// and tapping it turns the map back to north up.
class MapCompass extends StatefulWidget {
  const MapCompass({super.key, required this.controller});

  final MapController controller;

  @override
  State<MapCompass> createState() => _MapCompassState();
}

class _MapCompassState extends State<MapCompass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..addListener(_tick);
  late final StreamSubscription<MapEvent> _events;

  /// The map's rotation in degrees, as last reported.
  double _rotation = 0;

  /// The rotation the current animation started from.
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _events = widget.controller.mapEventStream.listen(_onEvent);
  }

  @override
  void dispose() {
    _events.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _onEvent(MapEvent e) {
    // someone turning or moving the map by hand takes over
    if (_anim.isAnimating && e.source != MapEventSource.mapController) {
      _anim.stop();
    }
    final r = e.camera.rotation;
    if ((r - _rotation).abs() > 0.1 && mounted) setState(() => _rotation = r);
  }

  void _northUp() {
    // the short way round: -180..180
    final from = ((_rotation % 360) + 540) % 360 - 180;
    if (from.abs() < 0.1) return;
    _from = from;
    _anim.forward(from: 0);
  }

  void _tick() {
    final t = Curves.easeOutCubic.transform(_anim.value);
    widget.controller.rotate(_from * (1 - t));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: const Key('mapCompass'),
      tooltip: l10n.mapNorthUp,
      onPressed: _northUp,
      // drawn like the other icons: their size and colour, an outline for
      // the south half, only the north tip filled in red
      icon: Builder(
        builder: (context) {
          final icon = IconTheme.of(context);
          return Transform.rotate(
            angle: _rotation * math.pi / 180,
            child: CustomPaint(
              key: const Key('mapCompassNeedle'),
              size: Size.square(icon.size ?? 24),
              painter: _NeedlePainter(
                north: const Color(0xFFE53935),
                south: icon.color ?? Theme.of(context).colorScheme.onSurface,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A compass needle pointing up: the north half filled red, the south half
/// an outline in the icon colour.
class _NeedlePainter extends CustomPainter {
  const _NeedlePainter({required this.north, required this.south});

  final Color north;
  final Color south;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final h = size.height * 0.42;
    final w = size.width * 0.2;
    final stroke = size.width / 14;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy + h)
        ..lineTo(c.dx + w, c.dy)
        ..lineTo(c.dx - w, c.dy)
        ..close(),
      Paint()
        ..color = south
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final tip = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    canvas.drawPath(tip, Paint()..color = north);
    canvas.drawPath(
      tip,
      Paint()
        ..color = north
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_NeedlePainter old) =>
      old.north != north || old.south != south;
}
