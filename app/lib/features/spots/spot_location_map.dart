import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../map/map_tiles.dart';

/// Interactive map of a spot with its dot: drag and pinch to look around,
/// cycle satellite (the default), map and transport map, jump back to the
/// spot. Inside a scrolling page, drags that start on the map move the map (flutter_map's
/// drag recognizers win over the page's).
class SpotLocationMap extends StatefulWidget {
  const SpotLocationMap({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 19,
    this.radius = 12,
  });

  final double lat;
  final double lon;

  /// Starts as close as the old top-down pictures did.
  final double zoom;
  final double radius;

  @override
  State<SpotLocationMap> createState() => _SpotLocationMapState();
}

class _SpotLocationMapState extends State<SpotLocationMap> {
  final _controller = MapController();
  MapBase _base = MapBase.satellite;

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
      borderRadius: BorderRadius.circular(widget.radius),
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
              buildBaseLayer(context, base: _base),
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
              buildBaseAttribution(context, base: _base),
            ],
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Column(
              children: [
                MapLayerButton(
                  key: const Key('spotMapLayer'),
                  base: _base,
                  onChanged: (b) => setState(() => _base = b),
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
