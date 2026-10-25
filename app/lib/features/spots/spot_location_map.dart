import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../map/map_tiles.dart';

/// Interactive map of a spot with its dot: drag and pinch to look around,
/// switch between map and satellite, jump back to the spot. Inside a
/// scrolling page, drags that start on the map move the map (flutter_map's
/// drag recognizers win over the page's).
class SpotLocationMap extends StatefulWidget {
  const SpotLocationMap({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 17,
  });

  final double lat;
  final double lon;
  final double zoom;

  @override
  State<SpotLocationMap> createState() => _SpotLocationMapState();
}

class _SpotLocationMapState extends State<SpotLocationMap> {
  final _controller = MapController();
  bool _satellite = false;

  LatLng get _spot => LatLng(widget.lat, widget.lon);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          FlutterMap(
            key: const Key('spotLocationMap'),
            mapController: _controller,
            options: MapOptions(
              initialCenter: _spot,
              initialZoom: widget.zoom,
              minZoom: 4,
              maxZoom: kMapMaxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (_satellite)
                buildSatelliteTileLayer()
              else
                buildTileLayer(context),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _spot,
                    width: 24,
                    height: 24,
                    child: Container(
                      key: const Key('spotLocationDot'),
                      decoration: BoxDecoration(
                        color: kAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(blurRadius: 4, color: Colors.black54),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_satellite)
                const RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [TextSourceAttribution('Esri World Imagery')],
                )
              else
                buildMapAttribution(context),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                IconButton.filledTonal(
                  key: const Key('spotMapLayer'),
                  tooltip: _satellite ? l.mapStreets : l.mapSatellite,
                  onPressed: () => setState(() => _satellite = !_satellite),
                  icon: Icon(
                    _satellite ? Icons.map_outlined : Icons.satellite_alt,
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('spotMapRecenter'),
                  tooltip: l.mapRecenter,
                  onPressed: () => _controller.move(_spot, widget.zoom),
                  icon: const Icon(Icons.center_focus_strong),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
