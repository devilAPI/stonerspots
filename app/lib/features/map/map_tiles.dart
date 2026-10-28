import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';

/// Overrides both tile styles (e.g. a self-hosted or paid provider):
/// `--dart-define=TILE_URL=https://.../{z}/{x}/{y}.png`
const String kTileUrlOverride = String.fromEnvironment('TILE_URL');

/// Highest zoom the user can reach. The tile servers have no tiles that
/// close (CARTO: up to 18 - it answers 403 above -, OSM: up to 19), so the
/// last levels are scaled-up tiles instead of blank ones.
const double kMapMaxZoom = 20;

const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// CARTO API key for the dark basemap:
/// `--dart-define=CARTO_KEY=...` (see `env/local.example.json`). It ends up in
/// every tile request, so treat it as public and restrict it in CARTO's
/// dashboard. Requests without a valid key return a watermarked tile, so the
/// dark style is only used when a key is present.
const String kCartoKey = String.fromEnvironment('CARTO_KEY');

String _cartoDarkUrl(String key) =>
    'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png?key=$key';

bool _usesCartoDark(BuildContext context, String cartoKey) =>
    Theme.of(context).brightness == Brightness.dark &&
    cartoKey.isNotEmpty &&
    kTileUrlOverride.isEmpty;

/// Tile layer matching the current theme: the dark CARTO map in dark mode
/// (with a key), otherwise standard OpenStreetMap.
TileLayer buildTileLayer(BuildContext context, {String cartoKey = kCartoKey}) {
  if (kTileUrlOverride.isNotEmpty) {
    return TileLayer(
      urlTemplate: kTileUrlOverride,
      userAgentPackageName: 'de.stonerspots.app',
    );
  }
  if (_usesCartoDark(context, cartoKey)) {
    return TileLayer(
      urlTemplate: _cartoDarkUrl(cartoKey),
      retinaMode: RetinaMode.isHighDensity(context),
      userAgentPackageName: 'de.stonerspots.app',
      maxNativeZoom: 18,
    );
  }
  return TileLayer(
    urlTemplate: _osmTiles,
    userAgentPackageName: 'de.stonerspots.app',
    maxNativeZoom: 19,
  );
}

/// Required credit for OpenStreetMap data and the CARTO basemap.
Widget buildMapAttribution(
  BuildContext context, {
  String cartoKey = kCartoKey,
}) {
  return RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    attributions: [
      const TextSourceAttribution('OpenStreetMap contributors'),
      if (_usesCartoDark(context, cartoKey))
        const TextSourceAttribution('CARTO'),
    ],
  );
}

/// Thunderforest API key for the public transport map (lines and stops):
/// `--dart-define=THUNDERFOREST_KEY=...`. Like the CARTO key it is public
/// in every tile request; without one the transport map is not offered.
const String kThunderforestKey = String.fromEnvironment('THUNDERFOREST_KEY');

/// [kThunderforestKey], overridable in tests.
final thunderforestKeyProvider = Provider<String>((ref) => kThunderforestKey);

/// Whether the transport map can be offered.
bool hasTransitMap({String key = kThunderforestKey}) =>
    key.isNotEmpty && kTileUrlOverride.isEmpty;

/// Thunderforest's Transport map, dark or light like the theme, with every
/// line and stop drawn in. Its free plan counts tiles per month, so it is
/// only loaded while switched on.
TileLayer buildTransitTileLayer(
  BuildContext context, {
  String key = kThunderforestKey,
}) {
  final style = Theme.of(context).brightness == Brightness.dark
      ? 'transport-dark'
      : 'transport';
  return TileLayer(
    urlTemplate:
        'https://tile.thunderforest.com/$style/{z}/{x}/{y}{r}.png?apikey=$key',
    retinaMode: RetinaMode.isHighDensity(context),
    userAgentPackageName: 'de.stonerspots.app',
    maxNativeZoom: 20,
  );
}

/// Esri World Imagery (top-down satellite). Credit "Esri World Imagery" must
/// stay visible wherever it is shown; check Esri's terms before a commercial
/// launch.
const _satelliteTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// Tiles are requested up to zoom 18 (Esri often has no sharper imagery and
/// answers with a "not yet available" tile); closer views are scaled up.
const int kSatelliteMaxNativeZoom = 18;

/// URL of one satellite tile.
String satelliteTileUrl(int z, int x, int y) => _satelliteTiles
    .replaceFirst('{z}', '$z')
    .replaceFirst('{x}', '$x')
    .replaceFirst('{y}', '$y');

/// Satellite layer for interactive maps.
TileLayer buildSatelliteTileLayer() => TileLayer(
  urlTemplate: _satelliteTiles,
  userAgentPackageName: 'de.stonerspots.app',
  maxNativeZoom: kSatelliteMaxNativeZoom,
);

/// The kinds of base map the map-type button cycles through.
enum MapBase { streets, satellite, transit }

/// The base map after [current]: street map, satellite, then the transport
/// map (only with a key), then back to the street map.
MapBase nextMapBase(MapBase current, {String transitKey = kThunderforestKey}) =>
    switch (current) {
      MapBase.streets => MapBase.satellite,
      MapBase.satellite =>
        hasTransitMap(key: transitKey) ? MapBase.transit : MapBase.streets,
      MapBase.transit => MapBase.streets,
    };

/// Base layer for a map that can switch to satellite imagery or the
/// transport map.
TileLayer buildBaseLayer(
  BuildContext context, {
  required MapBase base,
  String transitKey = kThunderforestKey,
}) => switch (base) {
  MapBase.streets => buildTileLayer(context),
  MapBase.satellite => buildSatelliteTileLayer(),
  MapBase.transit => buildTransitTileLayer(context, key: transitKey),
};

/// Credits for [buildBaseLayer]; Esri's stays visible, not behind a button.
Widget buildBaseAttribution(BuildContext context, {required MapBase base}) =>
    switch (base) {
      MapBase.streets => buildMapAttribution(context),
      MapBase.satellite => const Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 0, 6, 4),
          child: Text(
            'Esri World Imagery',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              shadows: [Shadow(blurRadius: 3, color: Colors.black)],
            ),
          ),
        ),
      ),
      MapBase.transit => const RichAttributionWidget(
        alignment: AttributionAlignment.bottomLeft,
        attributions: [
          TextSourceAttribution('Thunderforest'),
          TextSourceAttribution('OpenStreetMap contributors'),
        ],
      ),
    };

/// Round button showing the base map on screen; a tap switches to the next
/// one ([nextMapBase]).
class MapLayerButton extends StatelessWidget {
  const MapLayerButton({
    super.key,
    required this.base,
    required this.onChanged,
    this.transitKey = kThunderforestKey,
  });

  final MapBase base;
  final ValueChanged<MapBase> onChanged;
  final String transitKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, label) = switch (base) {
      MapBase.streets => (Icons.map_outlined, l.mapStreets),
      MapBase.satellite => (Icons.satellite_alt, l.mapSatellite),
      MapBase.transit => (Icons.directions_transit, l.mapTransit),
    };
    return IconButton.filledTonal(
      tooltip: label,
      onPressed: () => onChanged(nextMapBase(base, transitKey: transitKey)),
      icon: Icon(icon),
    );
  }
}
