import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/glass.dart';
import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';

/// The web app's stable version (the newest release; `/dev/` is the dev
/// build).
const kStableWebUrl = 'https://devilapi.github.io/stonerspots/';

/// The newest stable (non-prerelease) GitHub release.
const kStableReleaseUrl =
    'https://github.com/devilAPI/stonerspots/releases/latest';

/// How long "don't show again" keeps the notice away.
const kDevNoticeSnooze = Duration(days: 30);

const _snoozedUntilKey = 'dev_notice_snoozed_until';

/// Whether this is a dev build: CI builds dev releases with
/// `--dart-define=UPDATE_CHANNEL=dev` (releases: `release`; local builds:
/// none, so no notice).
final isDevBuildProvider = Provider<bool>(
  (ref) => const String.fromEnvironment('UPDATE_CHANNEL') == 'dev',
);

/// Whether the notice belongs here. On the web the dev build lives under
/// `/dev/`; before the first release the Pages workflow puts it on the
/// stable URL too, where offering "open the stable version" would only
/// reopen the same page. So on the web it shows under `/dev/` only.
final devNoticeHereProvider = Provider<bool>(
  (ref) => !kIsWeb || Uri.base.path.contains('/dev/'),
);

/// The clock for the snooze; tests replace it.
final devNoticeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Opens a link outside the app; tests replace it.
final devNoticeLauncherProvider = Provider<Future<void> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(
        uri,
        // on the web the stable version replaces this tab
        webOnlyWindowName: kIsWeb ? '_self' : null,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      ),
);

/// Shows the dev-build warning once after the app starts (in a dev build,
/// unless snoozed). Goes in MaterialApp's builder; [navigatorKey] is the
/// app's root navigator, which the dialog opens on.
class DevBuildNoticeHost extends ConsumerStatefulWidget {
  const DevBuildNoticeHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<DevBuildNoticeHost> createState() => _DevBuildNoticeHostState();
}

class _DevBuildNoticeHostState extends ConsumerState<DevBuildNoticeHost> {
  @override
  void initState() {
    super.initState();
    if (!ref.read(isDevBuildProvider) || !ref.read(devNoticeHereProvider)) {
      return;
    }
    final until = ref.read(settingsStoreProvider).getInt(_snoozedUntilKey);
    final now = ref.read(devNoticeClockProvider)();
    if (until != null && now.millisecondsSinceEpoch < until) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _show());
  }

  Future<void> _show() async {
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final snooze = await showDialog<bool>(
      context: context,
      builder: (_) => const DevBuildDialog(),
    );
    if (snooze ?? false) {
      final now = ref.read(devNoticeClockProvider)();
      await ref
          .read(settingsStoreProvider)
          .setInt(
            _snoozedUntilKey,
            now.add(kDevNoticeSnooze).millisecondsSinceEpoch,
          );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The warning; pops with whether "don't show again" was ticked.
class DevBuildDialog extends ConsumerStatefulWidget {
  const DevBuildDialog({super.key});

  @override
  ConsumerState<DevBuildDialog> createState() => _DevBuildDialogState();
}

class _DevBuildDialogState extends ConsumerState<DevBuildDialog> {
  bool _snooze = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GlassDialog(
      key: const Key('devBuildNotice'),
      title: Text(l.devBuildTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.devBuildBody),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('devBuildSnooze'),
            value: _snooze,
            onChanged: (v) => setState(() => _snooze = v ?? false),
            title: Text(l.devBuildSnooze),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('devBuildClose'),
          onPressed: () => Navigator.of(context).pop(_snooze),
          child: Text(l.close),
        ),
        FilledButton(
          key: const Key('devBuildStable'),
          onPressed: () {
            ref.read(devNoticeLauncherProvider)(
              Uri.parse(kIsWeb ? kStableWebUrl : kStableReleaseUrl),
            );
            Navigator.of(context).pop(_snooze);
          },
          child: Text(
            kIsWeb ? l.devBuildOpenStableWeb : l.devBuildLatestRelease,
          ),
        ),
      ],
    );
  }
}
