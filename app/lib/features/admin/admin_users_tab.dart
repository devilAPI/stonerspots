import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart' show Author;
import '../../l10n/app_localizations.dart';
import '../users/avatar_editor.dart';
import 'admin_bulk.dart';
import 'admin_controller.dart';
import 'admin_flows.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab>
    with AdminSelection<AdminUsersTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(adminUsersProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(adminUsersProvider);
    final ctrl = ref.read(adminUsersProvider.notifier);
    // admins (you included) are never banned or deleted in bulk
    final selectable = [
      for (final u in state.items)
        if (!u.isAdmin) u.id,
    ];
    final ids = current(selectable);
    return Column(
      children: [
        AdminSearchField(
          fieldKey: const Key('users-search'),
          hint: l10n.adminSearchUsers,
          initial: state.q,
          onSubmitted: ctrl.search,
        ),
        Expanded(
          child: AdminPagedList<AdminUser>(
            state: state,
            onRefresh: ctrl.refresh,
            onLoadMore: ctrl.loadMore,
            onRetry: ctrl.reload,
            itemBuilder: (ctx, u) {
              final theme = Theme.of(ctx);
              return AdminTile(
                key: Key('user-${u.id}'),
                selectKey: Key('user-select-${u.id}'),
                selected: selected.contains(u.id),
                onSelected: u.isAdmin || busy ? null : (on) => toggle(u.id, on),
                body: [
                  Row(
                    children: [
                      // tapping it changes or removes the picture
                      OwnAvatarEditor(
                        key: Key('user-avatar-${u.id}'),
                        moderating: true,
                        userId: u.id,
                        name: u.displayName,
                        url: u.avatarUrl,
                        radius: 16,
                        onChanged: (url) => ref
                            .read(adminUsersProvider.notifier)
                            .replace(
                              url == null
                                  ? u.withoutAvatar()
                                  : u.withAvatarUrl(url),
                            ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          u.displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (u.isAdmin) ...[
                        const SizedBox(width: 8),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(l10n.adminBadge),
                        ),
                      ],
                      if (u.banned) ...[
                        const SizedBox(width: 8),
                        Chip(
                          key: Key('user-banned-${u.id}'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colorScheme.errorContainer,
                          label: Text(l10n.adminBanned),
                        ),
                      ],
                    ],
                  ),
                  Text(u.email, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${l10n.adminUserSpots(u.spotCount)} · '
                    '${l10n.adminUserReports(u.reportsReceived)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    l10n.adminJoined(
                      MaterialLocalizations.of(ctx)
                          .formatShortDate(u.createdAt.toLocal()),
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                actions: [
                  OutlinedButton(
                    key: Key('user-edit-${u.id}'),
                    onPressed: () => editAdminUser(ctx, ref, u),
                    child: Text(l10n.adminEdit),
                  ),
                  OutlinedButton(
                    key: Key('user-spots-${u.id}'),
                    onPressed: () {
                      ref
                          .read(adminSpotsProvider.notifier)
                          .setOwner(
                            Author(id: u.id, displayName: u.displayName),
                          );
                      DefaultTabController.of(ctx).animateTo(2);
                    },
                    child: Text(l10n.adminShowUserSpots),
                  ),
                  if (u.avatarUrl != null)
                    OutlinedButton(
                      key: Key('user-avatar-remove-${u.id}'),
                      onPressed: () => removeAdminUserAvatar(ctx, ref, u),
                      child: Text(l10n.adminRemoveAvatar),
                    ),
                ],
              );
            },
          ),
        ),
        if (ids.isNotEmpty)
          AdminSelectionBar(
            count: ids.length,
            busy: busy,
            onSelectAll: () => setState(() => selected.addAll(selectable)),
            onClear: () => setState(selected.clear),
            onAction: (a) => run(
              (ids, onSend) =>
                  runUserBulk(context, ref, ids, a, onSend: onSend),
              ids,
            ),
            actions: [
              BulkAction('ban', Icons.block, l10n.adminBan),
              BulkAction('unban', Icons.lock_open, l10n.adminUnban),
              BulkAction(
                'delete',
                Icons.delete_outline,
                l10n.adminDelete,
                danger: true,
              ),
            ],
          ),
      ],
    );
  }
}
