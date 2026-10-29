import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/spot_tag_widgets.dart';
import '../../core/tag_catalog.dart';
import '../../l10n/app_localizations.dart';
import 'admin_actions.dart';
import 'admin_controller.dart';

/// One button of an [AdminSelectionBar].
class BulkAction {
  const BulkAction(this.id, this.icon, this.label, {this.danger = false});

  /// The API's action name; also keys the button (`bulk-<id>`).
  final String id;
  final IconData icon;
  final String label;
  final bool danger;
}

/// Bar under a list while rows are selected: how many, select all / clear,
/// and the [actions] for them.
class AdminSelectionBar extends StatelessWidget {
  const AdminSelectionBar({
    super.key,
    required this.count,
    required this.actions,
    required this.onAction,
    required this.onSelectAll,
    required this.onClear,
    this.busy = false,
  });

  final int count;
  final List<BulkAction> actions;
  final ValueChanged<String> onAction;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  /// An action is running: buttons are off.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('admin-selection-bar'),
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.adminSelected(count),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  IconButton(
                    key: const Key('bulk-select-all'),
                    tooltip: l10n.adminSelectAll,
                    onPressed: busy ? null : onSelectAll,
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    key: const Key('bulk-clear'),
                    tooltip: l10n.adminClearSelection,
                    onPressed: busy ? null : onClear,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              // wraps instead of scrolling: every action stays in sight
              Wrap(
                spacing: 4,
                children: [
                  for (final a in actions)
                    TextButton.icon(
                      key: Key('bulk-${a.id}'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: a.danger ? scheme.error : null,
                      ),
                      onPressed: busy ? null : () => onAction(a.id),
                      icon: Icon(a.icon),
                      label: Text(a.label),
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

Future<bool> _confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-bulk-delete'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.adminDelete),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Lets the admin pick one tag of the catalog; null when dismissed.
Future<String?> _pickTag(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final tags = ref.read(tagCatalogProvider);
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l10n.adminChooseTag),
      children: [
        for (final t in tags)
          SimpleDialogOption(
            key: Key('bulk-tag-${t.wire}'),
            onPressed: () => Navigator.pop(ctx, t.wire),
            child: Row(
              children: [
                Icon(spotTagIcon(t), size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(spotTagLabel(ctx, t))),
              ],
            ),
          ),
      ],
    ),
  );
}

void _report(BuildContext context, BulkResult<Object?> r) {
  final l10n = AppLocalizations.of(context);
  final parts = [
    if (r.items.isNotEmpty) l10n.adminBulkDone(r.items.length),
    if (r.deleted.isNotEmpty) l10n.adminBulkDeleted(r.deleted.length),
    if (r.skipped > 0) l10n.adminBulkSkipped(r.skipped),
  ];
  if (parts.isEmpty) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(parts.join(' · '))));
}

void _failed(BuildContext context) => ScaffoldMessenger.of(context)
    .showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).errorGeneric)),
    );

/// Bans, unbans or deletes the users [ids] (after asking, for delete) and
/// shows the result in the loaded lists. [onSend] runs once the request
/// goes out (after any question). True when the action ran.
Future<bool> runUserBulk(
  BuildContext context,
  WidgetRef ref,
  List<int> ids,
  String action, {
  VoidCallback? onSend,
}) async {
  final l10n = AppLocalizations.of(context);
  if (action == 'delete' &&
      !await _confirmDelete(
        context,
        title: l10n.adminDeleteUsersTitle(ids.length),
        body: l10n.adminDeleteUsersBody,
      )) {
    return false;
  }
  onSend?.call();
  try {
    final r = await ref
        .read(adminActionsRepositoryProvider)
        .bulkUsers(ids, action);
    ref.read(adminUsersProvider.notifier).applyBulk(r);
    if (r.deleted.isNotEmpty) {
      // their spots, and reports on everything they wrote, are gone too
      if (ref.read(adminSpotsProvider).loadedOnce) {
        ref.read(adminSpotsProvider.notifier).reload();
      }
      if (ref.read(adminReportsProvider).loadedOnce) {
        ref.read(adminReportsProvider.notifier).reload();
      }
    }
    if (context.mounted) _report(context, r);
    return true;
  } catch (_) {
    if (context.mounted) _failed(context);
    return false;
  }
}

/// Runs a bulk action on the spots [ids] (asking for the tag, or for
/// confirmation on delete) and shows the result in the loaded lists.
/// [onSend] runs once the request goes out. True when the action ran.
Future<bool> runSpotBulk(
  BuildContext context,
  WidgetRef ref,
  List<int> ids,
  String action, {
  VoidCallback? onSend,
}) async {
  final l10n = AppLocalizations.of(context);
  String? tag;
  if (action == 'add_tag' || action == 'remove_tag') {
    tag = await _pickTag(context, ref);
    if (tag == null) return false;
  } else if (action == 'delete' &&
      !await _confirmDelete(
        context,
        title: l10n.adminDeleteSpotsTitle(ids.length),
        body: l10n.adminDeleteSpotsBody,
      )) {
    return false;
  }
  if (!context.mounted) return false;
  onSend?.call();
  try {
    final r = await ref
        .read(adminActionsRepositoryProvider)
        .bulkSpots(ids, action, tag: tag);
    ref.read(adminSpotsProvider.notifier).applyBulk(r);
    final reports = ref.read(adminReportsProvider.notifier);
    for (final s in r.items) {
      reports.applySpot(s);
    }
    for (final id in r.deleted) {
      reports.removeSpot(id);
    }
    if (context.mounted) _report(context, r);
    return true;
  } catch (_) {
    if (context.mounted) _failed(context);
    return false;
  }
}
