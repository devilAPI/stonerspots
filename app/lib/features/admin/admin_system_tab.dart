import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'admin_actions.dart';

/// How often the tab asks for news while an update is under way.
const kUpdatePollInterval = Duration(seconds: 3);

/// Admin "Actions" tab: the installed backend version and buttons that make
/// the server update itself to the newest release or dev build.
class AdminSystemTab extends ConsumerStatefulWidget {
  const AdminSystemTab({super.key});

  @override
  ConsumerState<AdminSystemTab> createState() => _AdminSystemTabState();
}

class _AdminSystemTabState extends ConsumerState<AdminSystemTab> {
  SystemInfo? _info;
  bool _loadFailed = false;
  bool _requesting = false;

  /// The server stopped answering during an update: it is restarting.
  bool _restarting = false;
  Timer? _poll;

  AdminActionsRepository get _repo => ref.read(adminActionsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  bool get _updating => (_info?.update.busy ?? false) || _restarting;

  Future<void> _load() async {
    _poll?.cancel();
    try {
      final info = await _repo.system();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loadFailed = false;
        _restarting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // mid-update the API goes away for a moment while it restarts
        if (_updating) {
          _restarting = true;
        } else {
          _loadFailed = true;
        }
      });
    }
    if (mounted && _updating) _poll = Timer(kUpdatePollInterval, _load);
  }

  Future<void> _update(String channel) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.adminUpdateConfirmTitle),
        content: Text(
          channel == 'dev'
              ? l10n.adminUpdateConfirmDev
              : l10n.adminUpdateConfirmRelease,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('confirm-update'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.adminUpdate),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _requesting = true);
    try {
      final info = await _repo.requestUpdate(channel);
      if (!mounted) return;
      setState(() => _info = info);
      _poll?.cancel();
      _poll = Timer(kUpdatePollInterval, _load);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.adminUpdateRequestFailed)),
      );
      await _load(); // e.g. someone else started one meanwhile
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final info = _info;
    if (info == null) {
      return Center(
        child: _loadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.errorGeneric),
                  TextButton(onPressed: _load, child: Text(l10n.retry)),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    final theme = Theme.of(context);
    final canUpdate = info.updatesEnabled && !_updating && !_requesting;
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(12 + gutter, 12, 12 + gutter, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.dns_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.adminBackend,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        key: const Key('system-refresh'),
                        tooltip: l10n.retry,
                        onPressed: _updating ? null : _load,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  Text(
                    info.version.isEmpty
                        ? l10n.adminVersionUnknown
                        : l10n.adminBackendVersion(info.version),
                    key: const Key('system-version'),
                  ),
                  const SizedBox(height: 12),
                  _UpdateLine(info: info, restarting: _restarting),
                  if (!info.updatesEnabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.adminUpdatesDisabled,
                      key: const Key('system-updates-disabled'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        key: const Key('update-release'),
                        onPressed: canUpdate ? () => _update('release') : null,
                        icon: const Icon(Icons.system_update_alt),
                        label: Text(l10n.adminUpdateRelease),
                      ),
                      OutlinedButton.icon(
                        key: const Key('update-dev'),
                        onPressed: canUpdate ? () => _update('dev') : null,
                        icon: const Icon(Icons.science_outlined),
                        label: Text(l10n.adminUpdateDev),
                      ),
                    ],
                  ),
                  if (info.update.log.isNotEmpty)
                    ExpansionTile(
                      key: const Key('update-log'),
                      tilePadding: EdgeInsets.zero,
                      title: Text(l10n.adminUpdateLog),
                      // a failed update opens on its log
                      initiallyExpanded:
                          info.update.state == UpdateState.failed,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: SelectableText(
                            info.update.log.trimRight(),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line on the last or current update.
class _UpdateLine extends StatelessWidget {
  const _UpdateLine({required this.info, required this.restarting});

  final SystemInfo info;
  final bool restarting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final u = info.update;
    const spinner = SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    final (Widget icon, String text) = restarting
        ? (spinner, l10n.adminServerRestarting)
        : switch (u.state) {
            UpdateState.idle => (const SizedBox.shrink(), ''),
            UpdateState.pending => (spinner, l10n.adminUpdatePending),
            UpdateState.running => (spinner, l10n.adminUpdateRunning),
            UpdateState.done => (
              Icon(Icons.check_circle_outline, color: scheme.primary),
              u.from == u.to
                  ? l10n.adminUpdateUpToDate(u.to)
                  : l10n.adminUpdateDone(u.from, u.to),
            ),
            UpdateState.failed => (
              Icon(Icons.error_outline, color: scheme.error),
              l10n.adminUpdateFailed,
            ),
          };
    if (text.isEmpty) return const SizedBox.shrink();
    final finished = u.finishedAt;
    final settled =
        !restarting &&
        (u.state == UpdateState.done || u.state == UpdateState.failed);
    return Row(
      key: const Key('update-status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        icon,
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text),
              if (settled && finished != null)
                Text(
                  l10n.adminUpdateFinishedAt(_format(context, finished)),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _format(BuildContext context, DateTime d) {
    final loc = MaterialLocalizations.of(context);
    final local = d.toLocal();
    return '${loc.formatShortDate(local)} '
        '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
}
