import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_tiles.dart';

const LatLng kFallbackCenter = LatLng(49.5, 10.5);
const double kFallbackZoom = 6;

/// Map on which the user taps to place the spot's pin. The pin is shown at
/// [point]; the map starts at [initialCenter] (or the DACH fallback).
class LocationPicker extends StatelessWidget {
  const LocationPicker({
    super.key,
    required this.point,
    required this.onChanged,
    this.initialCenter,
  });

  final LatLng? point;
  final LatLng? initialCenter;
  final ValueChanged<LatLng> onChanged;

  @override
  Widget build(BuildContext context) {
    final center = point ?? initialCenter;
    return FlutterMap(
      options: MapOptions(
        initialCenter: center ?? kFallbackCenter,
        initialZoom: center == null ? kFallbackZoom : 15,
        onTap: (_, latLng) => onChanged(latLng),
      ),
      children: [
        buildTileLayer(context),
        if (point != null)
          MarkerLayer(
            markers: [
              Marker(
                point: point!,
                width: 40,
                height: 40,
                alignment: Alignment.topCenter,
                child: const Icon(
                  Icons.location_on,
                  size: 40,
                  color: Colors.red,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
