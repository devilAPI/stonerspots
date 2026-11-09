import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../l10n/app_localizations.dart';
import 'release.dart';
import 'update_controller.dart';

/// How the installed build is called: `dev-63` on the dev channel, the
/// version otherwise.
String installedLabel(UpdateState s, UpdaterConfig config) {
  final v = s.installed;
  if (v == null) return '';
  return config.channel == UpdateChannel.dev
      ? 'dev-${v.buildNumber}'
      : v.version;
}

/// Lays [UpdateBanner] over [child]. Goes in `MaterialApp.builder`, so it
/// is above every page but below the app's theme and localizations.
class UpdateBannerHost extends ConsumerStatefulWidget {
  const UpdateBannerHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends ConsumerState<UpdateBannerHost> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(updateControllerProvider.notifier).onAppStart(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final show = ref.watch(
      updateControllerProvider.select((s) => s.showBanner),
    );
    final safe = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        widget.child,
        if (show)
          Positioned(
            left: safe.left + 12,
            right: safe.right + 12,
            top: safe.top + 8,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: const UpdateBanner(),
              ),
            ),
          ),
      ],
    );
  }
}

/// "Update available (dev-123)" with what can be done about it. Never
/// blocks the app: it floats over it until "Later" or "Skip".
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(updateControllerProvider);
    final c = ref.read(updateControllerProvider.notifier);
    final release = s.release;
    if (release == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final installed = installedLabel(s, ref.watch(updaterConfigProvider));

    final String? status = switch (s.stage) {
      UpdateStage.downloading => l.updateDownloading(
        ((s.progress ?? 0) * 100).round(),
      ),
      UpdateStage.verifying => l.updateVerifying,
      UpdateStage.installing => l.updateInstalling,
      UpdateStage.handedOff => l.updateHandedOff,
      UpdateStage.failed => switch (s.problem) {
        UpdateProblem.needsInstallPermission => l.updatePermissionHint,
        UpdateProblem.signatureInvalid => l.updateErrorSignature,
        UpdateProblem.checksumMismatch => l.updateErrorChecksum,
        UpdateProblem.assetMissing => l.updateErrorMissing,
        UpdateProblem.installFailed => l.updateErrorInstall,
        _ => l.updateErrorDownload,
      },
      _ => switch (s.installBlocked) {
        UpdateProblem.noSigningKey => l.updateNoKeyHint,
        UpdateProblem.notWritable => l.updateNotWritableHint,
        _ => null,
      },
    };
    final working =
        s.stage == UpdateStage.downloading ||
        s.stage == UpdateStage.verifying ||
        s.stage == UpdateStage.installing;
    final pageOnly =
        s.installBlocked == UpdateProblem.noSigningKey ||
        s.installBlocked == UpdateProblem.notWritable;
    final failed = s.stage == UpdateStage.failed;

    return GlassSurface(
      key: const Key('updateBanner'),
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.updateAvailableTitle(release.tag),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: kOnGlass,
                        ),
                      ),
                      if (installed.isNotEmpty)
                        Text(
                          l.updateInstalledVersion(installed),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: kOnGlass.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 8),
              Text(
                status,
                key: const Key('updateStatus'),
                style: theme.textTheme.bodySmall?.copyWith(color: kOnGlass),
              ),
            ],
            if (s.stage == UpdateStage.downloading) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(value: s.progress),
              ),
            ],
            const SizedBox(height: 4),
            Wrap(
              alignment: WrapAlignment.end,
              children: working
                  ? [
                      TextButton(
                        key: const Key('updateCancel'),
                        onPressed:
                            s.stage == UpdateStage.downloading ||
                                s.stage == UpdateStage.verifying
                            ? c.cancel
                            : null,
                        child: Text(l.cancel),
                      ),
                    ]
                  : [
                      TextButton(
                        key: const Key('updateSkip'),
                        onPressed: c.skip,
                        child: Text(l.updateSkip),
                      ),
                      TextButton(
                        key: const Key('updateLater'),
                        onPressed: c.later,
                        child: Text(l.updateLater),
                      ),
                      if (failed &&
                          s.problem == UpdateProblem.needsInstallPermission)
                        TextButton(
                          key: const Key('updateOpenSettings'),
                          onPressed: c.openInstallPermissionSettings,
                          child: Text(l.updateOpenSettings),
                        ),
                      if (failed &&
                          !pageOnly &&
                          s.problem != UpdateProblem.needsInstallPermission)
                        TextButton(
                          key: const Key('updateOpenPage'),
                          onPressed: c.openReleasePage,
                          child: Text(l.updateOpenReleasePage),
                        ),
                      if (pageOnly)
                        FilledButton.tonal(
                          key: const Key('updateOpenPage'),
                          onPressed: c.openReleasePage,
                          child: Text(l.updateOpenReleasePage),
                        )
                      else
                        FilledButton.tonal(
                          key: const Key('updateNow'),
                          onPressed: c.updateNow,
                          child: Text(failed ? l.updateRetry : l.updateNow),
                        ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Updates" section of the settings; empty where the app can't update
/// itself (web, iOS).
class UpdateSettingsTiles extends ConsumerWidget {
  const UpdateSettingsTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(updaterConfigProvider);
    if (config.platform == null) return const SizedBox.shrink();
    if (config.channel == null) {
      return ListTile(
        key: const Key('checkUpdates'),
        leading: const Icon(Icons.system_update_alt),
        title: Text(l.settingsCheckUpdates),
        subtitle: Text(l.settingsNoUpdateChannel),
        enabled: false,
      );
    }
    final s = ref.watch(updateControllerProvider);
    final installed = installedLabel(s, config);
    final String? subtitle = switch (s.stage) {
      UpdateStage.checking => l.updateStatusChecking,
      UpdateStage.upToDate when s.problem == UpdateProblem.rateLimited =>
        l.updateStatusRateLimited,
      UpdateStage.upToDate => l.updateStatusUpToDate(installed),
      UpdateStage.failed when s.release == null =>
        s.problem == UpdateProblem.rateLimited
            ? l.updateStatusRateLimited
            : l.updateStatusOffline,
      _ when s.release != null => l.updateStatusAvailable(s.release!.tag),
      _ => installed.isEmpty ? null : l.updateInstalledVersion(installed),
    };
    final channel = ref.watch(updateChannelProvider)!;
    // Android refuses an APK with a lower build number than the installed one
    final downgradeNote =
        config.platform == UpdatePlatform.android &&
        config.channel == UpdateChannel.dev &&
        channel == UpdateChannel.release;
    return Column(
      children: [
        ListTile(
          key: const Key('updateChannel'),
          title: Text(l.settingsUpdateChannel),
          subtitle: Text(
            downgradeNote
                ? l.updateChannelAndroidDowngrade
                : l.settingsUpdateChannelHint,
          ),
          trailing: SegmentedButton<UpdateChannel>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: UpdateChannel.release,
                label: Text(l.updateChannelRelease),
              ),
              ButtonSegment(
                value: UpdateChannel.dev,
                label: Text(l.updateChannelDev),
              ),
            ],
            selected: {channel},
            onSelectionChanged: s.busy
                ? null
                : (picked) {
                    ref.read(updateChannelProvider.notifier).set(picked.first);
                    ref.read(updateControllerProvider.notifier).checkNow();
                  },
          ),
        ),
        SwitchListTile(
          key: const Key('autoUpdateCheck'),
          title: Text(l.settingsAutoUpdate),
          subtitle: Text(l.settingsAutoUpdateHint),
          value: ref.watch(autoUpdateCheckProvider),
          onChanged: ref.read(autoUpdateCheckProvider.notifier).set,
        ),
        ListTile(
          key: const Key('checkUpdates'),
          leading: s.stage == UpdateStage.checking
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          title: Text(l.settingsCheckUpdates),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: s.busy
              ? null
              : () => ref.read(updateControllerProvider.notifier).checkNow(),
        ),
      ],
    );
  }
}
