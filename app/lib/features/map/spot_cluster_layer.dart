import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';

import '../../core/theme.dart';

/// Clusters [markers]; tapping a number bubble zooms in so it splits.
class SpotClusterLayer extends StatelessWidget {
  const SpotClusterLayer({super.key, required this.markers});

  final List<Marker> markers;

  @override
  Widget build(BuildContext context) {
    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: 60,
        size: const Size(40, 40),
        markers: markers,
        builder: (context, markers) => Container(
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: kAccent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${markers.length}',
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
