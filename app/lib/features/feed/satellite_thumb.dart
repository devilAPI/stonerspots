import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../map/map_tiles.dart';

/// Non-interactive top-down satellite picture of a spot, used where a post
/// has no photo of its own.
class SatelliteThumb extends StatelessWidget {
  const SatelliteThumb({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 19,
  });

  final double lat;
  final double lon;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // IgnorePointer: the card list must keep scrolling and tapping.
          IgnorePointer(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                buildSatelliteTileLayer(),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: kAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Positioned(
            right: 6,
            bottom: 4,
            child: Text(
              'Esri World Imagery',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                shadows: [Shadow(blurRadius: 3, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
