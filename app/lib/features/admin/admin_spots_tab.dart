import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'admin_bulk.dart';
import 'admin_controller.dart';
import 'admin_flows.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

class AdminSpotsTab extends ConsumerStatefulWidget {
  const AdminSpotsTab({super.key});

  @override
  ConsumerState<AdminSpotsTab> createState() => _AdminSpotsTabState();
}

class _AdminSpotsTabState extends ConsumerState<AdminSpotsTab>
    with AdminSelection<AdminSpotsTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(adminSpotsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(adminSpotsProvider);
    final ctrl = ref.read(adminSpotsProvider.notifier);
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    final ids = current(state.items.map((s) => s.id));
    final filters = <(String, String?, String)>[
      ('all', null, l10n.statusAll),
      ('active', 'active', l10n.statusActive),
      ('hidden', 'hidden', l10n.statusHidden),
    ];
    return Column(
      children: [
        AdminSearchField(
          fieldKey: const Key('spots-search'),
          hint: l10n.adminSearchSpots,
          initial: state.q,
          onSubmitted: ctrl.search,
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 12 + gutter, vertical: 4),
            children: [
              if (state.owner case final owner?)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    key: const Key('spots-owner-filter'),
                    avatar: const Icon(Icons.person_outline),
                    label: Text(l10n.adminSpotsOf(owner.displayName)),
                    selected: true,
                    onDeleted: () => ctrl.setOwner(null),
                  ),
                ),
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: Key('spots-filter-${f.$1}'),
                    label: Text(f.$3),
                    selected: state.status == f.$2,
                    onSelected: (_) => ctrl.setStatus(f.$2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AdminPagedList<AdminSpot>(
            state: state,
            onRefresh: ctrl.refresh,
            onLoadMore: ctrl.loadMore,
            onRetry: ctrl.reload,
            itemBuilder: (ctx, s) {
              final theme = Theme.of(ctx);
              return AdminTile(
                key: Key('spot-${s.id}'),
                selectKey: Key('spot-select-${s.id}'),
                selected: selected.contains(s.id),
                onSelected: busy ? null : (on) => toggle(s.id, on),
                body: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          s.title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (s.locked)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Icon(
                            Icons.lock,
                            key: Key('spot-locked-${s.id}'),
                            size: 18,
                            semanticLabel: l10n.adminLocked,
                          ),
                        ),
                      const SizedBox(width: 8),
                      AdminStatusChip(s.status),
                    ],
                  ),
                  Text(
                    l10n.adminSpotAuthor(s.author.displayName),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    '${l10n.likesCount(s.likeCount)} · '
                    '${l10n.adminReportCount(s.reportCount)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                actions: [
                  OutlinedButton(
                    key: Key('spot-edit-${s.id}'),
                    onPressed: () =>
                        editAdminSpot(ctx, ref, s.id, fallbackTitle: s.title),
                    child: Text(l10n.adminEdit),
                  ),
                  OutlinedButton(
                    key: Key('spot-updates-${s.id}'),
                    onPressed: () => editAdminSpotUpdates(ctx, ref, s.id),
                    child: Text(l10n.adminEditUpdates),
                  ),
                  OutlinedButton(
                    key: Key('spot-open-${s.id}'),
                    onPressed: () => ctx.push('/spot/${s.id}'),
                    child: Text(l10n.openSpot),
                  ),
                  OutlinedButton(
                    key: Key('spot-remove-${s.id}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: () => confirmRemoveAdminSpot(
                      ctx,
                      ref,
                      spotId: s.id,
                      title: s.title,
                    ),
                    child: Text(l10n.adminRemove),
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
            onSelectAll: () =>
                setState(() => selected.addAll(state.items.map((s) => s.id))),
            onClear: () => setState(selected.clear),
            onAction: (a) => run(
              (ids, onSend) =>
                  runSpotBulk(context, ref, ids, a, onSend: onSend),
              ids,
            ),
            actions: [
              BulkAction('hide', Icons.visibility_off_outlined, l10n.adminHide),
              BulkAction('show', Icons.visibility_outlined, l10n.adminShow),
              BulkAction('lock', Icons.lock_outline, l10n.adminBulkLock),
              BulkAction('unlock', Icons.lock_open, l10n.adminBulkUnlock),
              BulkAction('add_tag', Icons.sell_outlined, l10n.adminAddTag),
              BulkAction(
                'remove_tag',
                Icons.label_off_outlined,
                l10n.adminRemoveTag,
              ),
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
