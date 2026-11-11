import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_localizations.dart';
import 'germany.dart';
import 'zone_consent.dart';
import 'zone_geo.dart';
import 'zone_models.dart';
import 'zone_tiles.dart';
import 'zones_repository.dart';

/// What the zone data says about one place.
enum ZoneVerdict {
  /// Within 100 m of a facility, or an explicit ban.
  forbidden,

  /// In a pedestrian zone (forbidden 7-20 h).
  pedestrian,

  /// Nothing found in the OSM data.
  clear,

  /// The data could not be loaded.
  unknown,
}

class ZoneStatus {
  const ZoneStatus(this.verdict, {this.hit, this.stale = false});

  static const unknown = ZoneStatus(ZoneVerdict.unknown);

  final ZoneVerdict verdict;

  /// The zone that decided it (forbidden / pedestrian).
  final ZoneHit? hit;

  /// Based on data the server could not refresh.
  final bool stale;
}

/// The status of [p] among [zones]: a facility zone beats a pedestrian zone.
ZoneStatus zoneStatusAt(LatLng p, List<Zone> zones, {bool stale = false}) {
  final hits = zonesAt(p, zones);
  if (hits.isEmpty) return ZoneStatus(ZoneVerdict.clear, stale: stale);
  final first = hits.first;
  return ZoneStatus(
    first.zone.isPedestrian ? ZoneVerdict.pedestrian : ZoneVerdict.forbidden,
    hit: first,
    stale: stale,
  );
}

/// Loads the zones around a place and judges it. Never throws: no data is
/// [ZoneStatus.unknown].
Future<ZoneStatus> checkZones(ZoneTileCache cache, LatLng p) async {
  try {
    // every place whose zone can reach p lies within the largest radius
    final near = await cache.zonesNear(p, kZoneRadius + 20);
    return zoneStatusAt(p, near.zones, stale: near.stale);
  } catch (_) {
    return ZoneStatus.unknown;
  }
}

/// How long a status that could not be checked waits before it is checked
/// again (while it is on screen): the server may be fetching the zones from
/// a slow Overpass server and have them by then.
final zoneStatusRetryProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

/// The zone status of a spot; only read while [zonesActiveProvider] holds.
/// "Could not be checked" is checked again every [zoneStatusRetryProvider]
/// while something shows it, and it is checked again whenever one of its
/// tiles arrives anew (the map then redraws it too).
final zoneStatusProvider = FutureProvider.autoDispose
    .family<ZoneStatus, ({double lat, double lon})>((ref, p) async {
      final cache = ref.watch(zoneTileCacheProvider);
      final at = LatLng(p.lat, p.lon);
      final status = await checkZones(cache, at);
      if (!ref.mounted) return status;
      final tiles = tilesAround(at, kZoneRadius + 20).toSet();
      final used = {for (final t in tiles) t: cache.peek(t)};
      final sub = cache.arrived.listen((e) {
        final (t, data) = e;
        if (tiles.contains(t) && !identical(used[t], data)) {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(sub.cancel);
      if (status.verdict == ZoneVerdict.unknown) {
        final retry = Timer(
          ref.read(zoneStatusRetryProvider),
          ref.invalidateSelf,
        );
        ref.onDispose(retry.cancel);
      }
      return status;
    });

/// One line for [s] ("In einer Verbotszone (Spielplatz, 40 m)").
String zoneStatusText(AppLocalizations l, ZoneStatus s) {
  switch (s.verdict) {
    case ZoneVerdict.forbidden:
      final hit = s.hit!;
      final kind = zoneKindLabel(l, hit.zone.kind);
      final m = hit.distance.round();
      return m <= 0
          ? l.zoneStatusForbiddenIn(kind)
          : l.zoneStatusForbiddenAt(kind, '$m');
    case ZoneVerdict.pedestrian:
      return l.zoneStatusPedestrian;
    case ZoneVerdict.clear:
      return l.zoneStatusClear;
    case ZoneVerdict.unknown:
      return l.zoneStatusUnknown;
  }
}

/// Status chip colours: red, yellow, green, grey.
({Color bg, Color fg, IconData icon}) _look(ZoneVerdict? v) => switch (v) {
  ZoneVerdict.forbidden => (
    bg: const Color(0xFFC62828),
    fg: Colors.white,
    icon: Icons.block,
  ),
  ZoneVerdict.pedestrian => (
    bg: const Color(0xFFF9A825),
    fg: Colors.black,
    icon: Icons.directions_walk,
  ),
  ZoneVerdict.clear => (
    bg: const Color(0xFF2E7D32),
    fg: Colors.white,
    icon: Icons.check_circle_outline,
  ),
  _ => (
    bg: const Color(0xFF616161),
    fg: Colors.white,
    icon: Icons.help_outline,
  ),
};

/// Whether a spot lies in a no-consumption zone, as a small coloured chip.
/// Tapping it explains the result and where the data comes from. Nothing
/// shows while the zone feature is off or outside Germany (§ 5 KCanG is
/// German law); the first time, it asks for the disclaimer.
class ZoneStatusChip extends ConsumerStatefulWidget {
  const ZoneStatusChip({
    super.key,
    required this.lat,
    required this.lon,
    this.compact = false,
  });

  final double lat;
  final double lon;

  /// Smaller, for the map's preview card.
  final bool compact;

  @override
  ConsumerState<ZoneStatusChip> createState() => _ZoneStatusChipState();
}

class _ZoneStatusChipState extends ConsumerState<ZoneStatusChip> {
  @override
  Widget build(BuildContext context) {
    if (!ref.watch(zonesEnabledProvider)) return const SizedBox.shrink();
    if (!inGermany(LatLng(widget.lat, widget.lon))) {
      return const SizedBox.shrink();
    }
    // not read yet: nothing; the map's zone button asks
    if (!ref.watch(zonesAcceptedProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final status = ref.watch(
      zoneStatusProvider((lat: widget.lat, lon: widget.lon)),
    );
    final s = status.value;
    final look = _look(s?.verdict);
    final text = s == null ? l.zoneStatusChecking : zoneStatusText(l, s);
    final small = widget.compact;
    final style =
        (small
                ? Theme.of(context).textTheme.labelSmall
                : Theme.of(context).textTheme.labelMedium)
            ?.copyWith(color: look.fg);
    return Semantics(
      button: true,
      label: text,
      excludeSemantics: true,
      child: Material(
        key: Key('zoneStatus-${s?.verdict.name ?? 'loading'}'),
        color: look.bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showZoneDisclaimer(
            context,
            header: s == null ? null : _StatusDetails(status: s),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 8 : 10,
              vertical: small ? 3 : 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s == null)
                  SizedBox.square(
                    dimension: small ? 12 : 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: look.fg,
                    ),
                  )
                else
                  Icon(look.icon, size: small ? 14 : 16, color: look.fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    text,
                    style: style,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.info_outline,
                  key: const Key('zoneStatusInfo'),
                  size: small ? 13 : 15,
                  color: look.fg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The status in the info dialog: which place, how far, how old the data.
class _StatusDetails extends StatelessWidget {
  const _StatusDetails({required this.status});

  final ZoneStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hit = status.hit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          zoneStatusText(l, status),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (hit != null) Text(zoneTitle(l, hit.zone)),
        if (status.stale) Text(l.zonesStaleNote),
      ],
    );
  }
}
