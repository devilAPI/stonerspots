import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What Stonerspots 1.0 has, in the order a user meets it.
List<(IconData, String, String)> whatsNewItems(AppLocalizations l) => [
  (Icons.map_outlined, l.whatsNewSearchTitle, l.whatsNewSearchBody),
  (Icons.place_outlined, l.whatsNewSpotsTitle, l.whatsNewSpotsBody),
  (
    Icons.dynamic_feed_outlined,
    l.whatsNewFollowingTitle,
    l.whatsNewFollowingBody,
  ),
  (Icons.person_outline, l.whatsNewProfilesTitle, l.whatsNewProfilesBody),
  (Icons.notifications_none, l.whatsNewActivityTitle, l.whatsNewActivityBody),
  (Icons.bookmark_border, l.whatsNewSavedTitle, l.whatsNewSavedBody),
  (
    Icons.admin_panel_settings_outlined,
    l.whatsNewAdminTitle,
    l.whatsNewAdminBody,
  ),
  (Icons.system_update_outlined, l.whatsNewUpdatesTitle, l.whatsNewUpdatesBody),
];

/// Shows the "What's new in 1.0" dialog.
Future<void> showWhatsNewDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      key: const Key('whatsNewDialog'),
      title: Text(l.whatsNewTitle),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, title, body) in whatsNewItems(l))
                ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: Text(body),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.close),
        ),
      ],
    );
  },
);
