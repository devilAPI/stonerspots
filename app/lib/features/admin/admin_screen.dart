import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import 'admin_controller.dart';
import 'admin_edit_dialogs.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

String _categoryLabel(AppLocalizations l, String c) => switch (c) {
  'bench' => l.categoryBench,
  'river' => l.categoryRiver,
  'lake' => l.categoryLake,
  'viewpoint' => l.categoryViewpoint,
  'forest' => l.categoryForest,
  'park' => l.categoryPark,
  _ => l.categoryOther,
};

String _formatDateTime(BuildContext context, DateTime d) {
  final loc = MaterialLocalizations.of(context);
  final local = d.toLocal();
  return '${loc.formatShortDate(local)} '
      '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// Moderation page for admins: reports, users and spots.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Keep the (auto-disposed) list states alive while the page is open, so
    // switching tabs does not drop searches or loaded pages.
    ref.listen(adminReportsProvider, (_, _) {});
    ref.listen(adminUsersProvider, (_, _) {});
    ref.listen(adminSpotsProvider, (_, _) {});
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.adminReports),
              Tab(text: l10n.adminUsers),
              Tab(text: l10n.adminSpots),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ReportsTab(), _UsersTab(), _SpotsTab()],
        ),
      ),
    );
  }
}

/// Confirms and performs the removal; reports the result in a snackbar.
Future<void> _confirmRemoveSpot(
  BuildContext context,
  WidgetRef ref, {
  required int spotId,
  required String title,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.adminRemoveTitle),
      content: Text(l10n.adminRemoveBody(title)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-remove-spot'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.adminRemove),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await removeAdminSpot(ref, spotId);
    messenger.showSnackBar(SnackBar(content: Text(l10n.adminSpotRemoved)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
}

/// Confirms and removes the reported review/update; reports the result in a
/// snackbar.
Future<void> _confirmRemoveTarget(
  BuildContext context,
  WidgetRef ref,
  AdminReport report,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final review = report.targetType == 'review';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        review ? l10n.adminRemoveReviewTitle : l10n.adminRemoveUpdateTitle,
      ),
      content: Text(
        review ? l10n.adminRemoveReviewBody : l10n.adminRemoveUpdateBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-remove-target'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.adminRemove),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await removeAdminReportTarget(ref, report);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          review ? l10n.adminReviewRemoved : l10n.adminUpdateRemoved,
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
}

/// Read-only row of five stars, [rating] of them filled.
class _StarRow extends StatelessWidget {
  const _StarRow(this.rating);
  final int rating;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: AppLocalizations.of(context).adminRatingStars(rating),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              i <= rating ? Icons.star : Icons.star_border,
              size: 18,
              color: color,
            ),
        ],
      ),
    );
  }
}

Future<void> _editUser(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  int? me;
  try {
    me = (await ref.read(authControllerProvider.future))?.id;
  } catch (_) {}
  if (!context.mounted) return;
  final updated = await showEditUserDialog(
    context,
    user: user,
    currentUserId: me,
  );
  if (updated == null) return;
  ref.read(adminUsersProvider.notifier).replace(updated);
  messenger.showSnackBar(SnackBar(content: Text(l10n.adminUserSaved)));
}

/// Opens the spot edit dialog. [fallbackTitle] is used to look the spot up on
/// the server when it is not in the loaded Spots list (e.g. from a report).
Future<void> _editSpot(
  BuildContext context,
  WidgetRef ref,
  int spotId, {
  required String fallbackTitle,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  AdminSpot? spot;
  for (final s in ref.read(adminSpotsProvider).items) {
    if (s.id == spotId) spot = s;
  }
  if (spot == null) {
    try {
      final page = await ref
          .read(adminRepositoryProvider)
          .spots(q: fallbackTitle.isEmpty ? null : fallbackTitle, limit: 50);
      for (final s in page.items) {
        if (s.id == spotId) spot = s;
      }
    } catch (_) {}
  }
  if (spot == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    return;
  }
  if (!context.mounted) return;
  final updated = await showEditSpotDialog(context, spot: spot);
  if (updated == null) return;
  applyEditedSpot(ref, updated);
  messenger.showSnackBar(SnackBar(content: Text(l10n.adminSpotSaved)));
}

Future<void> _dismissOne(
  BuildContext context,
  WidgetRef ref,
  AdminReport report,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await dismissAdminReport(ref, report);
    messenger.showSnackBar(SnackBar(content: Text(l10n.adminReportDismissed)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
}

Future<void> _dismissAll(
  BuildContext context,
  WidgetRef ref,
  AdminReport report, {
  required bool restore,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.adminDismissAllTitle),
      content: Text(
        restore
            ? l10n.adminDismissAllRestoreBody
            : l10n.adminDismissAllKeepBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-dismiss-all'),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            restore ? l10n.adminDismissAllRestore : l10n.adminDismissAllKeep,
          ),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    final removed = await dismissAdminReportsOfTarget(
      ref,
      report,
      restore: restore,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.adminReportsDismissed(removed))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
  }
}

/// Scrollable, centred list with loading / empty / error states, pull to
/// refresh and "load more" near the end.
class _PagedList<T> extends StatefulWidget {
  const _PagedList({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetry,
    required this.itemBuilder,
  });

  final AdminListState<T> state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRetry;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  State<_PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<_PagedList<T>> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    // A short first page may not fill the viewport, so nothing would scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });

    if (state.error != null && state.items.isEmpty && !state.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorGeneric),
            TextButton(onPressed: widget.onRetry, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (!state.loadedOnce || (state.loading && state.items.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }
    final Widget list;
    if (state.items.isEmpty) {
      list = ListView(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.noResults)),
        ],
      );
    } else {
      list = ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (ctx, i) => i >= state.items.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : widget.itemBuilder(ctx, state.items[i]),
      );
    }
    return RefreshIndicator(onRefresh: widget.onRefresh, child: list);
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final hidden = status == 'hidden';
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(hidden ? l10n.statusHidden : l10n.statusActive),
      backgroundColor: hidden ? scheme.errorContainer : null,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.body, this.actions = const []});
  final List<Widget> body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...body,
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: actions),
            ),
        ],
      ),
    ),
  );
}

/// Search box that only queries on submit (Enter / search key).
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.fieldKey,
    required this.hint,
    required this.initial,
    required this.onSubmitted,
  });

  final Key fieldKey;
  final String hint;
  final String initial;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final gutter = sideGutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(12 + gutter, 8, 12 + gutter, 4),
      child: TextFormField(
        key: fieldKey,
        initialValue: initial,
        textInputAction: TextInputAction.search,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- reports

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(adminReportsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(adminReportsProvider.notifier);
    return _PagedList<AdminReport>(
      state: ref.watch(adminReportsProvider),
      onRefresh: ctrl.refresh,
      onLoadMore: ctrl.loadMore,
      onRetry: ctrl.reload,
      itemBuilder: (ctx, r) => _ReportTile(report: r),
    );
  }
}

class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.report});
  final AdminReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = report.target;
    final isUpdate = report.targetType == 'update';
    final isReview = report.targetType == 'review';
    return _Tile(
      key: Key('report-${report.id}'),
      body: [
        Row(
          children: [
            Expanded(
              child: Text(report.reason, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.adminReportCount(report.reportCount),
              style: theme.textTheme.labelLarge,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.adminReportedBy(
            report.reporter.displayName,
            report.reporter.email,
          ),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          _formatDateTime(context, report.createdAt),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (!t.exists)
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(l10n.adminTargetDeleted),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isReview || isUpdate)
                      Text(
                        isReview
                            ? l10n.adminTargetReview
                            : l10n.adminTargetUpdate,
                        style: theme.textTheme.labelLarge,
                      ),
                    if (isReview && t.rating > 0) _StarRow(t.rating),
                    if ((isReview || isUpdate) && t.body.isNotEmpty)
                      Text(
                        t.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      isUpdate ? l10n.adminUpdateOn(t.title) : t.title,
                      style: isUpdate || isReview
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.titleSmall,
                    ),
                    if (isReview && t.author != null)
                      Text(
                        t.author!.displayName,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(t.status),
            ],
          ),
      ],
      actions: [
        OutlinedButton(
          key: Key('report-dismiss-${report.id}'),
          onPressed: () => _dismissOne(context, ref, report),
          child: Text(l10n.adminDismiss),
        ),
        if (t.exists && (isReview || isUpdate))
          OutlinedButton(
            key: Key('report-remove-target-${report.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => _confirmRemoveTarget(context, ref, report),
            child: Text(
              isReview ? l10n.adminRemoveReview : l10n.adminRemoveUpdate,
            ),
          ),
        if (t.exists && t.spotId != null) ...[
          OutlinedButton(
            key: Key('report-open-${report.id}'),
            onPressed: () => context.push('/spot/${t.spotId}'),
            child: Text(l10n.adminOpenSpot),
          ),
          if (!isReview) ...[
            OutlinedButton(
              key: Key('report-edit-spot-${report.id}'),
              onPressed: () =>
                  _editSpot(context, ref, t.spotId!, fallbackTitle: t.title),
              child: Text(l10n.adminEditSpot),
            ),
            OutlinedButton(
              key: Key('report-remove-${report.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _confirmRemoveSpot(
                context,
                ref,
                spotId: t.spotId!,
                title: t.title,
              ),
              child: Text(l10n.adminRemoveSpot),
            ),
          ],
        ],
        PopupMenuButton<bool>(
          key: Key('report-more-${report.id}'),
          tooltip: l10n.adminMoreActions,
          onSelected: (restore) =>
              _dismissAll(context, ref, report, restore: restore),
          itemBuilder: (_) => [
            PopupMenuItem(
              key: Key('report-dismiss-all-restore-${report.id}'),
              value: true,
              child: Text(l10n.adminDismissAllRestore),
            ),
            PopupMenuItem(
              key: Key('report-dismiss-all-keep-${report.id}'),
              value: false,
              child: Text(l10n.adminDismissAllKeep),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ users

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
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
    return Column(
      children: [
        _SearchField(
          fieldKey: const Key('users-search'),
          hint: l10n.adminSearchUsers,
          initial: state.q,
          onSubmitted: ctrl.search,
        ),
        Expanded(
          child: _PagedList<AdminUser>(
            state: state,
            onRefresh: ctrl.refresh,
            onLoadMore: ctrl.loadMore,
            onRetry: ctrl.reload,
            itemBuilder: (ctx, u) {
              final theme = Theme.of(ctx);
              return _Tile(
                key: Key('user-${u.id}'),
                body: [
                  Row(
                    children: [
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
                    onPressed: () => _editUser(ctx, ref, u),
                    child: Text(l10n.adminEdit),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ spots

class _SpotsTab extends ConsumerStatefulWidget {
  const _SpotsTab();

  @override
  ConsumerState<_SpotsTab> createState() => _SpotsTabState();
}

class _SpotsTabState extends ConsumerState<_SpotsTab> {
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
    final filters = <(String, String?, String)>[
      ('all', null, l10n.statusAll),
      ('active', 'active', l10n.statusActive),
      ('hidden', 'hidden', l10n.statusHidden),
    ];
    return Column(
      children: [
        _SearchField(
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
          child: _PagedList<AdminSpot>(
            state: state,
            onRefresh: ctrl.refresh,
            onLoadMore: ctrl.loadMore,
            onRetry: ctrl.reload,
            itemBuilder: (ctx, s) {
              final theme = Theme.of(ctx);
              return _Tile(
                key: Key('spot-${s.id}'),
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
                      const SizedBox(width: 8),
                      _StatusChip(s.status),
                    ],
                  ),
                  Text(
                    '${_categoryLabel(l10n, s.category)} · '
                    '${l10n.adminSpotAuthor(s.author.displayName)}',
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
                        _editSpot(ctx, ref, s.id, fallbackTitle: s.title),
                    child: Text(l10n.adminEdit),
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
                    onPressed: () => _confirmRemoveSpot(
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
      ],
    );
  }
}
