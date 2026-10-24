import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const String kTileUrl = String.fromEnvironment('TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
const LatLng kFallbackCenter = LatLng(49.5, 10.5);
const double kFallbackZoom = 6;

/// Injectable current-position lookup.
abstract class LocationService {
  /// Null when permission is denied or the position is unavailable.
  Future<LatLng?> currentPosition();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LatLng?> currentPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      final p = await Geolocator.getCurrentPosition();
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }
}

final locationServiceProvider =
    Provider<LocationService>((ref) => GeolocatorLocationService());

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
        TileLayer(
          urlTemplate: kTileUrl,
          userAgentPackageName: 'de.stonerspots.app',
        ),
        if (point != null)
          MarkerLayer(markers: [
            Marker(
              point: point!,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on, size: 40, color: Colors.red),
            ),
          ]),
      ],
    );
  }
}
