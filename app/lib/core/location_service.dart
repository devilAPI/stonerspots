import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Resolves the device position. Injectable so tests never touch the platform.
abstract class LocationService {
  /// Null when permission is denied or the position is unavailable.
  Future<LatLng?> currentPosition();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<LatLng?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
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

/// The answer to one position lookup; [position] null when it failed.
class LocationLookup {
  const LocationLookup(this.position);
  final LatLng? position;
}

/// Hands every answer of [inner] to [onResult] too, so a feature that only
/// uses a position when there happens to be one needs no lookup of its own
/// (a second permission request at the same time would fail).
class ObservedLocationService implements LocationService {
  ObservedLocationService(this.inner, this.onResult);

  final LocationService inner;
  final void Function(LocationLookup) onResult;

  @override
  Future<LatLng?> currentPosition() async {
    final position = await inner.currentPosition();
    onResult(LocationLookup(position));
    return position;
  }
}

class LastLocationLookup extends Notifier<LocationLookup?> {
  @override
  LocationLookup? build() => null;

  void record(LocationLookup lookup) => state = lookup;
}

/// The latest lookup of this run, whichever screen made it; null before the
/// first one.
final lastLocationLookupProvider =
    NotifierProvider<LastLocationLookup, LocationLookup?>(
      LastLocationLookup.new,
    );

final locationServiceProvider = Provider<LocationService>(
  (ref) => ObservedLocationService(
    GeolocatorLocationService(),
    ref.read(lastLocationLookupProvider.notifier).record,
  ),
);
