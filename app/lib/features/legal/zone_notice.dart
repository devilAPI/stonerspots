import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';
import 'legal_links.dart';
import 'legal_pages.dart';

/// Whether the map's one-time notice about no-smoking zones was closed.
final zoneNoticeSeenProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('zone_notice_seen'),
);

/// Shown on the map until closed once (stored with the other settings):
/// the zones come from OpenStreetMap and are no legal advice, with the gist of the
/// law and a link to the community rules.
class ZoneNotice extends ConsumerWidget {
  const ZoneNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(zoneNoticeSeenProvider)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Material(
        key: const Key('zoneNotice'),
        color: theme.colorScheme.surfaceContainerHigh,
        elevation: 4,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.zoneNoticeTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  l10n.zoneNoticeBody,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('zoneNoticeRules'),
                    onPressed: () => openLegalPage(context, kRulesPath),
                    child: Text(l10n.legalRules),
                  ),
                  TextButton(
                    key: const Key('zoneNoticeDismiss'),
                    onPressed: () =>
                        ref.read(zoneNoticeSeenProvider.notifier).set(true),
                    child: Text(l10n.zoneNoticeDismiss),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
