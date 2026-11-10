import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'admin_controller.dart';
import 'admin_flows.dart';
import 'admin_models.dart';
import 'admin_widgets.dart';

class AdminReportsTab extends ConsumerStatefulWidget {
  const AdminReportsTab({super.key});

  @override
  ConsumerState<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends ConsumerState<AdminReportsTab> {
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
    return AdminPagedList<AdminReport>(
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
    final isComment = report.targetType == 'comment';
    // reviews and comments: the spot itself is not what was reported
    final isSub = isReview || isComment;
    return AdminTile(
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
          formatAdminDateTime(context, report.createdAt),
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
                    if (isSub || isUpdate)
                      Text(
                        isComment
                            ? l10n.adminTargetComment
                            : isReview
                            ? l10n.adminTargetReview
                            : l10n.adminTargetUpdate,
                        style: theme.textTheme.labelLarge,
                      ),
                    if (isReview && t.rating > 0) AdminStarRow(t.rating),
                    if ((isSub || isUpdate) && t.body.isNotEmpty)
                      Text(
                        t.body,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      isComment
                          ? l10n.adminCommentOn(t.title)
                          : isUpdate
                          ? l10n.adminUpdateOn(t.title)
                          : t.title,
                      style: isUpdate || isSub
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.titleSmall,
                    ),
                    if (isSub && t.author != null)
                      Text(
                        t.author!.displayName,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AdminStatusChip(t.status),
            ],
          ),
      ],
      actions: [
        OutlinedButton(
          key: Key('report-dismiss-${report.id}'),
          onPressed: () => dismissOneReport(context, ref, report),
          child: Text(l10n.adminDismiss),
        ),
        if (t.exists && (isSub || isUpdate))
          OutlinedButton(
            key: Key('report-remove-target-${report.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => confirmRemoveReportTarget(context, ref, report),
            child: Text(
              isComment
                  ? l10n.adminRemoveComment
                  : isReview
                  ? l10n.adminRemoveReview
                  : l10n.adminRemoveUpdate,
            ),
          ),
        if (t.exists && t.spotId != null) ...[
          OutlinedButton(
            key: Key('report-open-${report.id}'),
            onPressed: () => context.push('/spot/${t.spotId}'),
            child: Text(l10n.adminOpenSpot),
          ),
          if (!isSub) ...[
            OutlinedButton(
              key: Key('report-edit-spot-${report.id}'),
              onPressed: () => editAdminSpot(
                context,
                ref,
                t.spotId!,
                fallbackTitle: t.title,
              ),
              child: Text(l10n.adminEditSpot),
            ),
            OutlinedButton(
              key: Key('report-remove-${report.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => confirmRemoveAdminSpot(
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
              dismissAllReports(context, ref, report, restore: restore),
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
