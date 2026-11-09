import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';
import '../legal/legal_pages.dart' show kRulesPath;
import 'zone_models.dart';

/// The zone feature (map layer, spot status, add-spot check) is on. The
/// map's zone button switches it; off by default.
final zonesEnabledProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('zones_enabled'),
);

/// The user has read the zone disclaimer in this session (not stored: the
/// first time zones are switched on or would show after a start, it comes
/// again).
final zonesAcceptedProvider = NotifierProvider<SessionFlag, bool>(
  SessionFlag.new,
);

/// A yes/no that lives only as long as the app runs.
class SessionFlag extends Notifier<bool> {
  SessionFlag([this.initial = false]);

  final bool initial;

  @override
  bool build() => initial;

  void set(bool value) => state = value;
}

/// Zones may be fetched and shown: switched on and the disclaimer read.
final zonesActiveProvider = Provider<bool>(
  (ref) => ref.watch(zonesEnabledProvider) && ref.watch(zonesAcceptedProvider),
);

/// The disclaimer on screen, so the map, a status chip and the add-spot
/// check that all want it at once share one dialog.
final _pendingConsentProvider = Provider<_PendingConsent>(
  (ref) => _PendingConsent(),
);

class _PendingConsent {
  Future<bool>? future;
}

/// Makes sure the user has read the disclaimer before anything zone-related
/// shows. Asks once per session: "Got it" remembers that until the app
/// closes, "Cancel" (or closing the dialog) switches the zone feature off. True when zones may be shown.
Future<bool> ensureZoneConsent(BuildContext context, WidgetRef ref) {
  if (!ref.read(zonesEnabledProvider)) return Future.value(false);
  if (ref.read(zonesAcceptedProvider)) return Future.value(true);
  final pending = ref.read(_pendingConsentProvider);
  return pending.future ??= () async {
    try {
      final ok = await showZoneDisclaimer(context, firstUse: true) ?? false;
      if (ok) {
        ref.read(zonesAcceptedProvider.notifier).set(true);
      } else {
        ref.read(zonesEnabledProvider.notifier).set(false);
      }
      return ok;
    } finally {
      pending.future = null;
    }
  }();
}

/// The disclaimer. On first use it asks ("Got it" / "Cancel", returns
/// whether accepted); later (the info buttons) it only informs.
Future<bool?> showZoneDisclaimer(
  BuildContext context, {
  bool firstUse = false,
  Widget? header,
}) => showDialog<bool>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: !firstUse,
  builder: (context) {
    final l = AppLocalizations.of(context);
    return GlassDialog(
      key: const Key('zoneDisclaimer'),
      title: Text(l.zonesTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[header, const SizedBox(height: 12)],
          for (final t in [
            l.zonesDisclaimerData,
            l.zonesDisclaimerDistance,
            l.zonesDisclaimerMissing,
            l.zonesDisclaimerLaw,
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(t)),
                ],
              ),
            ),
          Text(
            l.zonesSource,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: kOnGlass),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('zoneDisclaimerRules'),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              icon: const Icon(Icons.gavel_outlined, size: 18),
              label: Text(l.legalRules),
              // on top of the dialog: back leads here again
              onPressed: () => context.push(kRulesPath),
            ),
          ),
        ],
      ),
      actions: firstUse
          ? [
              TextButton(
                key: const Key('zoneDisclaimerCancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.cancel),
              ),
              FilledButton(
                key: const Key('zoneDisclaimerOk'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.zonesDisclaimerOk),
              ),
            ]
          : [
              TextButton(
                key: const Key('zoneDisclaimerClose'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l.close),
              ),
            ],
    );
  },
);

/// The kind of place, for people.
String zoneKindLabel(AppLocalizations l, ZoneKind k) => switch (k) {
  ZoneKind.school => l.zoneKindSchool,
  ZoneKind.kindergarten => l.zoneKindKindergarten,
  ZoneKind.childcare => l.zoneKindChildcare,
  ZoneKind.youth => l.zoneKindYouth,
  ZoneKind.playground => l.zoneKindPlayground,
  ZoneKind.sports => l.zoneKindSports,
  ZoneKind.explicit => l.zoneKindExplicit,
  ZoneKind.pedestrian => l.zoneKindPedestrian,
};

/// "Spielplatz Musterweg", "Grundschule Am Park (Schule)" or just the kind.
String zoneTitle(AppLocalizations l, Zone z) {
  final kind = zoneKindLabel(l, z.kind);
  if (z.name.isEmpty) return kind;
  if (z.name.toLowerCase().contains(kind.toLowerCase())) return z.name;
  return l.zoneTitleNamed(z.name, kind);
}
