import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../../core/theme.dart';

IconData categoryIcon(String category) => switch (category) {
      'bench' => Icons.chair_alt,
      'river' => Icons.water,
      'lake' => Icons.pool,
      'viewpoint' => Icons.landscape,
      'forest' => Icons.park,
      'park' => Icons.nature_people,
      _ => Icons.place,
    };

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
        child: Icon(categoryIcon(spot.category),
            size: large ? 28 : 18, color: Colors.black),
      ),
    ),
  );
}
