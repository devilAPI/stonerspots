import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dialogs.dart';
import '../../core/models.dart' show FeedItem;
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../spots/update_actions.dart';
import '../spots/updates_repository.dart';
import '../users/author_link.dart' show avatarOverridesProvider;
import 'admin_controller.dart';
import 'admin_edit_dialogs.dart';
import 'admin_models.dart';
import 'admin_repository.dart';

// What the admin lists' buttons do: ask where needed, call the server, say
// how it went in a snackbar.

/// Confirms and performs the removal; reports the result in a snackbar.
Future<void> confirmRemoveAdminSpot(
  BuildContext context,
  WidgetRef ref, {
  required int spotId,
  required String title,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await confirmDialog(
    context,
    title: l10n.adminRemoveTitle,
    body: l10n.adminRemoveBody(title),
    confirm: l10n.adminRemove,
    confirmKey: const Key('confirm-remove-spot'),
    danger: true,
  );
  if (!ok) return;
  try {
    await removeAdminSpot(ref, spotId);
    messenger.showText(l10n.adminSpotRemoved);
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
  }
}

/// Confirms and removes the reported review/update; reports the result in a
/// snackbar.
Future<void> confirmRemoveReportTarget(
  BuildContext context,
  WidgetRef ref,
  AdminReport report,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final review = report.targetType == 'review';
  final comment = report.targetType == 'comment';
  final ok = await confirmDialog(
    context,
    title: comment
        ? l10n.adminRemoveCommentTitle
        : review
        ? l10n.adminRemoveReviewTitle
        : l10n.adminRemoveUpdateTitle,
    body: comment
        ? l10n.adminRemoveCommentBody
        : review
        ? l10n.adminRemoveReviewBody
        : l10n.adminRemoveUpdateBody,
    confirm: l10n.adminRemove,
    confirmKey: const Key('confirm-remove-target'),
    danger: true,
  );
  if (!ok) return;
  try {
    await removeAdminReportTarget(ref, report);
    messenger.showText(
      comment
          ? l10n.adminCommentRemoved
          : review
          ? l10n.adminReviewRemoved
          : l10n.adminUpdateRemoved,
    );
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
  }
}

Future<void> editAdminUser(
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
  messenger.showText(l10n.adminUserSaved);
}

/// Asks, then removes [user]'s profile picture.
Future<void> removeAdminUserAvatar(
  BuildContext context,
  WidgetRef ref,
  AdminUser user,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await confirmDialog(
    context,
    title: l10n.adminRemoveAvatar,
    body: l10n.adminRemoveAvatarBody(user.displayName),
    confirm: l10n.adminRemoveAvatar,
    confirmKey: const Key('user-avatar-remove-confirm'),
  );
  if (!ok) return;
  try {
    await ref.read(adminRepositoryProvider).deleteUserAvatar(user.id);
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
    return;
  }
  ref.read(adminUsersProvider.notifier).replace(user.withoutAvatar());
  ref.read(avatarOverridesProvider.notifier).set(user.id, null);
  messenger.showText(l10n.adminAvatarRemoved);
}

/// Opens the spot edit dialog. [fallbackTitle] is used to look the spot up on
/// the server when it is not in the loaded Spots list (e.g. from a report).
Future<void> editAdminSpot(
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
    messenger.showText(l10n.errorGeneric);
    return;
  }
  if (!context.mounted) return;
  final updated = await showEditSpotDialog(context, spot: spot);
  if (updated == null) return;
  applyEditedSpot(ref, updated);
  messenger.showText(l10n.adminSpotSaved);
}

Future<void> dismissOneReport(
  BuildContext context,
  WidgetRef ref,
  AdminReport report,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await dismissAdminReport(ref, report);
    messenger.showText(l10n.adminReportDismissed);
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
  }
}

Future<void> dismissAllReports(
  BuildContext context,
  WidgetRef ref,
  AdminReport report, {
  required bool restore,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final ok = await confirmDialog(
    context,
    title: l10n.adminDismissAllTitle,
    body: restore
        ? l10n.adminDismissAllRestoreBody
        : l10n.adminDismissAllKeepBody,
    confirm: restore ? l10n.adminDismissAllRestore : l10n.adminDismissAllKeep,
    confirmKey: const Key('confirm-dismiss-all'),
  );
  if (!ok) return;
  try {
    final removed = await dismissAdminReportsOfTarget(
      ref,
      report,
      restore: restore,
    );
    messenger.showText(l10n.adminReportsDismissed(removed));
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
  }
}

/// Lets the admin pick one of the spot's updates and edit it.
Future<void> editAdminSpotUpdates(
  BuildContext context,
  WidgetRef ref,
  int spotId,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final List<FeedItem> updates;
  try {
    updates = await ref.read(spotUpdatesRepositoryProvider).listForSpot(spotId);
  } catch (_) {
    messenger.showText(l10n.errorGeneric);
    return;
  }
  if (!context.mounted) return;
  if (updates.isEmpty) {
    messenger.showText(l10n.updatesNone);
    return;
  }
  if (await adminEditOneOf(context, updates)) {
    messenger.showText(l10n.adminUpdateSaved);
  }
}
