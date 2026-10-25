import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../feed/feed_card.dart' show relativeTime;

String updateTagLabel(AppLocalizations l, UpdateTag tag) => switch (tag) {
  UpdateTag.note => l.updateTagNote,
  UpdateTag.stillGood => l.updateTagStillGood,
  UpdateTag.crowded => l.updateTagCrowded,
  UpdateTag.dirty => l.updateTagDirty,
  UpdateTag.closed => l.updateTagClosed,
};

/// One entry of a spot's update timeline.
class UpdateTile extends StatelessWidget {
  const UpdateTile({
    super.key,
    required this.item,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onPhotoTap,
    this.canChangeOwn = true,
    this.onAdminEdit,
    this.onAdminHide,
    this.onAdminDelete,
  });

  final FeedItem item;

  /// Own updates get edit and delete (unless [canChangeOwn] is false, on a
  /// locked spot); others get report, or the admin menu for admins.
  final bool isMine;
  final bool canChangeOwn;

  /// Set for admins: a menu to edit, hide or delete someone else's update.
  final VoidCallback? onAdminEdit;
  final VoidCallback? onAdminHide;
  final VoidCallback? onAdminDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final void Function(int index) onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = StringBuffer(item.author.displayName)
      ..write(' · ')
      ..write(relativeTime(item.createdAt));
    if (item.editedAt != null) meta.write(' · ${l.updateEdited}');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meta.toString(), style: theme.textTheme.bodySmall),
                if (item.tag != UpdateTag.note) ...[
                  const SizedBox(height: 4),
                  Chip(
                    label: Text(updateTagLabel(l, item.tag)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.body),
                ],
                if (item.photos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: item.photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => InkWell(
                        key: Key('updateTilePhoto_$i'),
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => onPhotoTap(i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: CachedNetworkImage(
                              imageUrl: item.photos[i].thumbUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isMine && !canChangeOwn)
            const SizedBox.shrink()
          else if (isMine) ...[
            IconButton(
              key: Key('updateEdit_${item.id}'),
              tooltip: l.updateActionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              key: Key('updateDelete_${item.id}'),
              tooltip: l.updateActionDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ] else if (onAdminEdit != null)
            PopupMenuButton<String>(
              key: Key('updateAdmin_${item.id}'),
              tooltip: l.adminMoreActions,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onSelected: (v) => switch (v) {
                'edit' => onAdminEdit?.call(),
                'hide' => onAdminHide?.call(),
                _ => onAdminDelete?.call(),
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: Key('updateAdminEdit_${item.id}'),
                  value: 'edit',
                  child: Text(l.adminEditUpdate),
                ),
                PopupMenuItem(
                  key: Key('updateAdminHide_${item.id}'),
                  value: 'hide',
                  child: Text(l.adminHideUpdate),
                ),
                PopupMenuItem(
                  key: Key('updateAdminDelete_${item.id}'),
                  value: 'delete',
                  child: Text(l.adminRemoveUpdate),
                ),
              ],
            )
          else
            IconButton(
              key: Key('updateReport_${item.id}'),
              tooltip: l.report,
              icon: const Icon(Icons.flag_outlined),
              onPressed: onReport,
            ),
        ],
      ),
    );
  }
}
