import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../map/map_tiles.dart';

const LatLng kFallbackCenter = LatLng(49.5, 10.5);
const double kFallbackZoom = 6;
const double kFocusZoom = 17;

/// A request to recentre the map. A NEW instance (compared with [identical])
/// moves the map, even when it holds the same coordinates as the last one.
class MapFocus {
  const MapFocus(this.center, [this.zoom = kFocusZoom]);

  final LatLng center;
  final double zoom;
}

/// Map on which the user taps to place the spot's pin. The pin is shown at
/// [point]; the map starts at [initialCenter] (or the DACH fallback) and moves
/// whenever a new [focus] arrives.
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.point,
    required this.onChanged,
    this.initialCenter,
    this.focus,
  });

  final LatLng? point;
  final LatLng? initialCenter;
  final MapFocus? focus;
  final ValueChanged<LatLng> onChanged;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final MapController _controller = MapController();

  @override
  void didUpdateWidget(LocationPicker old) {
    super.didUpdateWidget(old);
    final f = widget.focus;
    if (f != null && !identical(f, old.focus)) {
      _controller.move(f.center, f.zoom);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = widget.point;
    final focus = widget.focus;
    final center = focus?.center ?? point ?? widget.initialCenter;
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        // Only used when the map is first built; a focus that was set before
        // the picker existed is honoured here.
        initialCenter: center ?? kFallbackCenter,
        initialZoom: focus?.zoom ?? (center == null ? kFallbackZoom : 15),
        onTap: (_, latLng) => widget.onChanged(latLng),
      ),
      children: [
        buildTileLayer(context),
        if (point != null)
          MarkerLayer(
            markers: [
              Marker(
                point: point,
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
