import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What 2.0 brought, in the order a user meets it.
List<(IconData, String, String)> whatsNew20(AppLocalizations l) => [
  (Icons.person_outline, l.whatsNewProfilesTitle, l.whatsNewProfilesBody),
  (
    Icons.dynamic_feed_outlined,
    l.whatsNewFollowingTitle,
    l.whatsNewFollowingBody,
  ),
  (Icons.chat_bubble_outline, l.whatsNewCommentsTitle, l.whatsNewCommentsBody),
  (Icons.notifications_none, l.whatsNewActivityTitle, l.whatsNewActivityBody),
  (Icons.search, l.whatsNewSearchTitle, l.whatsNewSearchBody),
  (Icons.wb_sunny_outlined, l.whatsNewWeatherTitle, l.whatsNewWeatherBody),
];

/// Shows the "What's new in 2.0" dialog.
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
              for (final (icon, title, body) in whatsNew20(l))
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
