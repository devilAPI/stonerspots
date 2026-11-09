import 'package:app/core/settings.dart';
import 'package:app/features/zones/zone_consent.dart';
import 'package:app/features/zones/zone_geo.dart';
import 'package:app/features/zones/zone_layer.dart';
import 'package:app/features/zones/zone_models.dart';
import 'package:app/features/zones/zone_tiles.dart';
import 'package:app/features/zones/zones_repository.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:latlong2/latlong.dart';

/// Middle of tile (2406, 578) in Munich.
const base = LatLng(48.13, 11.57);
final frame = LocalFrame(base);

/// The point [east] / [north] metres from [base].
LatLng at(double east, double north) => frame.offset(east, north);

/// A square area of [size] metres centred [east]/[north] from [base].
Zone square(
  String id,
  ZoneKind kind, {
  double east = 0,
  double north = 0,
  double size = 40,
  String name = '',
}) {
  final h = size / 2;
  final ring = [
    at(east - h, north - h),
    at(east + h, north - h),
    at(east + h, north + h),
    at(east - h, north + h),
    at(east - h, north - h),
  ];
  return Zone(
    id: id,
    kind: kind,
    name: name,
    shape: ZoneShape.polygon,
    parts: [ring],
  );
}

Zone point(String id, ZoneKind kind, LatLng p, {String name = ''}) => Zone(
  id: id,
  kind: kind,
  name: name,
  shape: ZoneShape.point,
  parts: [
    [p],
  ],
);

Zone line(String id, ZoneKind kind, List<LatLng> pts, {String name = ''}) =>
    Zone(id: id, kind: kind, name: name, shape: ZoneShape.line, parts: [pts]);

/// Answers tile requests from [tiles] (empty tile otherwise), or fails.
class FakeZonesRepository implements ZonesRepository {
  FakeZonesRepository([this.tiles = const {}]);

  final Map<ZoneTileId, ZoneData> tiles;
  final asked = <ZoneTileId>[];
  bool fail = false;
  bool stale = false;

  @override
  Future<ZoneData> fetchTile(ZoneTileId tile) async {
    asked.add(tile);
    if (fail) throw Exception('offline');
    final d = tiles[tile];
    return ZoneData(zones: d?.zones ?? const [], stale: stale);
  }
}

/// A repository with [zones] in the tile of [base].
FakeZonesRepository repoWith(List<Zone> zones) => FakeZonesRepository({
  ZoneTileId.at(base.latitude, base.longitude): ZoneData(zones: zones),
});

/// Overrides for widget tests: zones on or off, disclaimer read or not.
List<Override> overridesFor(
  ZonesRepository repo, {
  bool enabled = true,
  bool accepted = true,
  SettingsStore? store,
  DateTime Function()? now,
}) {
  final s = store ?? SettingsStore.memory();
  s.setBool('zones_enabled', enabled);
  return [
    settingsStoreProvider.overrideWithValue(s),
    zonesAcceptedProvider.overrideWith(() => SessionFlag(accepted)),
    zonesRepositoryProvider.overrideWithValue(repo),
    zoneDebounceProvider.overrideWithValue(Duration.zero),
    if (now != null) zoneClockProvider.overrideWithValue(now),
  ];
}

/// Zones switched off: for tests of pages that show zone chips but are not
/// about them.
final zonesOff = zonesEnabledProvider.overrideWith(
  () => BoolSetting('zones_enabled'),
);
