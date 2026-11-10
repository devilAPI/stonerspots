import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'zone_consent.dart';
import 'zone_layer_controller.dart';
import 'zone_paint.dart';

/// The zones drawn on the map (a [FlutterMap] child, above the base map).
/// Shows only while the zone feature is on, the disclaimer read and the
/// map zoomed in to street level.
class ZoneLayer extends ConsumerWidget {
  const ZoneLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(zonesActiveProvider)) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    if (camera.zoom < kZoneMinZoom) return const SizedBox.shrink();
    ref.read(zoneLayerControllerProvider.notifier).onCamera(camera);
    final s = ref.watch(zoneLayerControllerProvider);
    if (s.tiles.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: CustomPaint(
          key: const Key('zoneLayer'),
          size: camera.size,
          isComplex: true,
          painter: ZonePainter(
            camera: camera,
            tiles: s.tiles.values.toList(growable: false),
            banNow: s.banNow,
          ),
        ),
      ),
    );
  }
}
