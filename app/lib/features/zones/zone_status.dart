import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../l10n/app_localizations.dart';
import 'zone_consent.dart';
import 'zone_geo.dart';
import 'zone_models.dart';
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

/// The zone status of a spot; only read while [zonesActiveProvider] holds.
final zoneStatusProvider = FutureProvider.autoDispose
    .family<ZoneStatus, ({double lat, double lon})>(
      (ref, p) =>
          checkZones(ref.watch(zoneTileCacheProvider), LatLng(p.lat, p.lon)),
    );

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
/// shows while the zone feature is off; the first time, it asks for the
/// disclaimer.
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
  bool _asked = false;

  void _ask() {
    if (_asked) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ensureZoneConsent(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(zonesEnabledProvider)) return const SizedBox.shrink();
    if (!ref.watch(zonesAcceptedProvider)) {
      _ask();
      return const SizedBox.shrink();
    }
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
