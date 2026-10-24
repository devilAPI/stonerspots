import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

/// Marker icon from the spot's tags only; first match in this priority.
IconData spotIcon(List<SpotTag> tags) {
  if (tags.contains(SpotTag.roof)) return Icons.roofing;
  if (tags.contains(SpotTag.water)) return Icons.water_drop;
  if (tags.contains(SpotTag.view)) return Icons.landscape;
  if (tags.contains(SpotTag.seating)) return Icons.chair_alt;
  return Icons.place;
}

Marker buildSpotMarker(Spot spot, {required bool large, VoidCallback? onTap}) {
  final size = large ? 52.0 : 34.0;
  return Marker(
    key: ValueKey('spot-${spot.id}'),
    point: LatLng(spot.lat, spot.lon),
    width: size,
    height: size,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: large ? 3 : 2),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black45)],
        ),
        child: Icon(
          spotIcon(spot.tags),
          size: large ? 28 : 18,
          color: Colors.black,
        ),
      ),
    ),
  );
}
