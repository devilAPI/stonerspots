import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Overrides both tile styles (e.g. a self-hosted or paid provider):
/// `--dart-define=TILE_URL=https://.../{z}/{x}/{y}.png`
const String kTileUrlOverride = String.fromEnvironment('TILE_URL');

const _lightTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// CARTO "Dark Matter" (OpenStreetMap data). Needs CARTO attribution; check
/// their terms before a commercial launch.
const _darkTiles =
    'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

/// Tile layer matching the current theme: dark map in dark mode.
TileLayer buildTileLayer(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final custom = kTileUrlOverride.isNotEmpty;
  return TileLayer(
    urlTemplate: custom ? kTileUrlOverride : (dark ? _darkTiles : _lightTiles),
    subdomains: !custom && dark
        ? const ['a', 'b', 'c', 'd']
        : const ['a', 'b', 'c'],
    retinaMode: !custom && dark && RetinaMode.isHighDensity(context),
    userAgentPackageName: 'de.stonerspots.app',
    maxNativeZoom: 19,
  );
}

/// Required credit for OpenStreetMap data and the CARTO basemap.
Widget buildMapAttribution(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    attributions: [
      const TextSourceAttribution('OpenStreetMap contributors'),
      if (dark && kTileUrlOverride.isEmpty)
        const TextSourceAttribution('CARTO'),
    ],
  );
}

/// Esri World Imagery (top-down satellite). Credit "Esri World Imagery" must
/// stay visible wherever it is shown; check Esri's terms before a commercial
/// launch.
const _satelliteTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

TileLayer buildSatelliteTileLayer() => TileLayer(
  urlTemplate: _satelliteTiles,
  userAgentPackageName: 'de.stonerspots.app',
  maxNativeZoom: 19,
);
