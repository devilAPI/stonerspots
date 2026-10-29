import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_edit_dialogs.dart';
import '../admin/admin_models.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart' show relativeTime;
import 'update_composer.dart';
import 'updates_repository.dart';

// Actions on one update, shared by the spot page and the feed. Each resolves
// to true when the update changed, so the caller can reload its list.

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String confirm,
  required Key confirmKey,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// The author edits their own update.
Future<bool> editOwnUpdate(BuildContext context, FeedItem item) async =>
    await showUpdateComposer(context, spotId: item.spot.id, editing: item) ==
    true;

/// The author deletes their own update, after asking.
Future<bool> deleteOwnUpdate(
  BuildContext context,
  WidgetRef ref,
  FeedItem item,
) async {
  final l = AppLocalizations.of(context);
  final ok = await _confirm(
    context,
    title: l.updateDeleteTitle,
    confirm: l.updateDeleteConfirm,
    confirmKey: const Key('updateDeleteConfirm'),
  );
  if (!ok) return false;
  try {
    await ref.read(spotUpdatesRepositoryProvider).delete(item.id);
    return true;
  } catch (_) {
    if (context.mounted) _snack(context, l.errorGeneric);
    return false;
  }
}

/// An admin edits anyone's update: text, tag, owner and photos.
Future<bool> adminEditUpdate(BuildContext context, FeedItem item) async =>
    await showAdminUpdateDialog(context, item) == true;

Future<bool> adminHideUpdate(
  BuildContext context,
  WidgetRef ref,
  FeedItem item,
) async {
  final l = AppLocalizations.of(context);
  try {
    await ref
        .read(adminRepositoryProvider)
        .updateUpdate(item.id, const AdminUpdatePatch(status: 'hidden'));
    if (context.mounted) _snack(context, l.adminUpdateHidden);
    return true;
  } catch (_) {
    if (context.mounted) _snack(context, l.errorGeneric);
    return false;
  }
}

/// An admin removes anyone's update, after asking. A 404 counts as done.
Future<bool> adminDeleteUpdate(
  BuildContext context,
  WidgetRef ref,
  FeedItem item,
) async {
  final l = AppLocalizations.of(context);
  final ok = await _confirm(
    context,
    title: l.adminRemoveUpdateTitle,
    body: l.adminRemoveUpdateBody,
    confirm: l.adminRemove,
    confirmKey: const Key('adminUpdateDeleteConfirm'),
  );
  if (!ok) return false;
  try {
    await ref.read(adminRepositoryProvider).deleteUpdate(item.id);
    if (context.mounted) _snack(context, l.adminUpdateRemoved);
  } catch (e) {
    if (!(e is ApiException && e.status == 404) && context.mounted) {
      _snack(context, l.errorGeneric);
    }
  }
  return true;
}

/// Lets an admin pick one of [updates] and edit it; resolves to true when
/// anything was saved.
Future<bool> adminEditOneOf(
  BuildContext context,
  List<FeedItem> updates,
) async {
  final l = AppLocalizations.of(context);
  final picked = await showModalBottomSheet<FeedItem>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.adminPickUpdate,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final u in updates)
                    ListTile(
                      key: Key('pickUpdate_${u.id}'),
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(
                        u.body.isEmpty ? l.adminPhotos : u.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${u.author.displayName} · '
                        '${relativeTime(u.createdAt)}',
                      ),
                      onTap: () => Navigator.pop(ctx, u),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (picked == null || !context.mounted) return false;
  return adminEditUpdate(context, picked);
}

/// The "⋮" menu on a feed card: edit or delete for the author (unless the
/// spot is locked), edit, hide or remove for admins. Empty for everyone else.
class UpdateMenu extends ConsumerWidget {
  const UpdateMenu({super.key, required this.item, required this.onChanged});

  final FeedItem item;

  /// Called after the update was changed, hidden or deleted.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authControllerProvider.select((s) => s.value));
    if (me == null) return const SizedBox.shrink();
    final mine = item.author.id == me.id;
    final admin = me.isAdmin;
    if (!admin && !(mine && !item.spot.locked)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    Future<void> run(Future<bool> Function() action) async {
      if (await action()) onChanged();
    }

    return PopupMenuButton<String>(
      key: Key('updateMenu_${item.id}'),
      icon: Icon(
        admin && !mine ? Icons.admin_panel_settings_outlined : Icons.more_vert,
      ),
      onSelected: (v) => switch (v) {
        'edit' => run(() => editOwnUpdate(context, item)),
        'delete' => run(() => deleteOwnUpdate(context, ref, item)),
        'admin-edit' => run(() => adminEditUpdate(context, item)),
        'admin-hide' => run(() => adminHideUpdate(context, ref, item)),
        _ => run(() => adminDeleteUpdate(context, ref, item)),
      },
      itemBuilder: (_) => [
        if (mine) ...[
          PopupMenuItem(
            key: Key('updateMenuEdit_${item.id}'),
            value: 'edit',
            child: ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l.updateActionEdit),
            ),
          ),
          PopupMenuItem(
            key: Key('updateMenuDelete_${item.id}'),
            value: 'delete',
            child: ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l.updateActionDelete),
            ),
          ),
        ],
        if (admin) ...[
          if (mine) const PopupMenuDivider(),
          PopupMenuItem(
            key: Key('updateMenuAdminEdit_${item.id}'),
            value: 'admin-edit',
            child: ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(l.adminEditUpdate),
            ),
          ),
          if (!mine) ...[
            PopupMenuItem(
              key: Key('updateMenuAdminHide_${item.id}'),
              value: 'admin-hide',
              child: ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(l.adminHideUpdate),
              ),
            ),
            PopupMenuItem(
              key: Key('updateMenuAdminDelete_${item.id}'),
              value: 'admin-delete',
              child: ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: Text(l.adminRemoveUpdate),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
