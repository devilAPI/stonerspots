import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/glass.dart';
import '../../l10n/app_localizations.dart';
import 'germany.dart';
import 'zone_consent.dart';
import 'zone_geo.dart';
import 'zone_models.dart';
import 'zone_status.dart';
import 'zones_repository.dart';

/// How long adding a spot waits for the zone data before going ahead
/// without it.
const Duration kZoneCheckTimeout = Duration(seconds: 8);

/// Before a new spot is saved: the zone [p] lies in, if any (after the
/// first-use disclaimer). Null also outside Germany (no zones there), when
/// the zone feature is off, the disclaimer was cancelled or no data came in
/// time.
Future<ZoneHit?> zoneForNewSpot(
  BuildContext context,
  WidgetRef ref,
  LatLng p,
) async {
  if (!inGermany(p)) return null;
  if (!await ensureZoneConsent(context, ref)) return null;
  final status = await checkZones(
    ref.read(zoneTileCacheProvider),
    p,
  ).timeout(kZoneCheckTimeout, onTimeout: () => ZoneStatus.unknown);
  return status.hit;
}

/// Asks whether to add a spot in [hit]'s zone anyway. Only warns, never
/// blocks (OSM can be wrong), also for an explicit smoking:cannabis=no.
/// True to go ahead.
Future<bool> confirmZoneWarning(BuildContext context, ZoneHit hit) async {
  final l = AppLocalizations.of(context);
  final title = zoneTitle(l, hit.zone);
  final m = hit.distance.round();
  final text = switch (hit.zone.kind) {
    ZoneKind.pedestrian => l.addSpotZonePedestrian(title),
    ZoneKind.explicit => l.addSpotZoneExplicit(title),
    _ => l.addSpotZoneWarning(m > 0 ? '$title, $m m' : title),
  };
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => GlassDialog(
      key: const Key('addSpotZoneWarning'),
      title: Text(l.addSpotZoneTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 10),
          Text(
            l.addSpotZoneNote,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: kOnGlass),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('zoneWarningCancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('zoneAddAnyway'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.addAnyway),
        ),
      ],
    ),
  );
  return go ?? false;
}
