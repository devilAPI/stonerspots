import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/models.dart' show FeedItem;
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart' show relativeTime;
import '../spots/spot_api.dart';
import '../users/author_link.dart';
import 'comment_models.dart';
import 'comments_controller.dart';

/// How many of the newest comments show while the thread is collapsed.
const kCommentPreviewCount = 2;

/// The comments of one update, right under it: the newest
/// [kCommentPreviewCount], a button that expands the whole thread in place,
/// and a one-line composer. Logged out, the composer is a login button.
class UpdateComments extends ConsumerStatefulWidget {
  const UpdateComments({
    super.key,
    required this.item,
    this.initiallyExpanded = false,
  });

  final FeedItem item;
  final bool initiallyExpanded;

  @override
  ConsumerState<UpdateComments> createState() => _UpdateCommentsState();
}

class _UpdateCommentsState extends ConsumerState<UpdateComments> {
  final _text = TextEditingController();
  late bool _expanded = widget.initiallyExpanded;
  bool _sending = false;

  int get _id => widget.item.id;

  CommentThreadController get _thread =>
      ref.read(commentThreadProvider(_id).notifier);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    // Nothing to fetch for an update without comments.
    if (widget.item.commentCount > 0) {
      Future.microtask(() {
        if (mounted) _thread.load();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _counted(int delta) => ref
      .read(commentCountsProvider.notifier)
      .adjust(_id, widget.item.commentCount, delta);

  String _errorText(AppLocalizations l, Object e) => switch (e) {
    ApiException(status: 429) => l.commentsQuota,
    ApiException(status: 404) => l.commentsGone,
    _ => l.errorGeneric,
  };

  void _snack(String text) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(text)));

  void _login() => context.push('/login');

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _thread.post(body);
      _counted(1);
      _text.clear();
    } catch (e) {
      if (mounted) _snack(_errorText(l, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment c) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.commentDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('commentDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.commentDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _thread.delete(c);
      _counted(-1);
    } catch (e) {
      if (mounted) _snack(_errorText(l, e));
    }
  }

  Future<void> _report(Comment c) async {
    final l = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await ref.read(spotApiProvider).report('comment', c.id, reason);
      if (mounted) _snack(l.commentReported);
    } catch (e) {
      if (mounted) _snack(_errorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final thread = ref.watch(commentThreadProvider(_id));
    final count = CommentCounts.of(
      ref.watch(commentCountsProvider),
      widget.item,
    );
    final user = ref.watch(authControllerProvider).value;
    final items = thread.items;

    // Pages come oldest first: the newest are on the last one.
    if (!_expanded &&
        thread.hasMore &&
        !thread.loading &&
        !thread.loadingMore &&
        thread.error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _thread.loadMore();
      });
    }

    final shown = _expanded || items.length <= kCommentPreviewCount
        ? items
        : items.sublist(items.length - kCommentPreviewCount);
    final total = count > items.length ? count : items.length;
    final small = theme.textTheme.labelLarge;

    Widget textButton(String key, String label, VoidCallback onPressed) =>
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: Key('${key}_$_id'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: small,
            ),
            onPressed: onPressed,
            child: Text(label),
          ),
        );

    return Column(
      key: Key('updateComments_$_id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty && thread.error != null)
          Row(
            children: [
              Flexible(
                child: Text(
                  _errorText(l, thread.error!),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                key: Key('commentsRetry_$_id'),
                onPressed: _thread.load,
                child: Text(l.retry),
              ),
            ],
          ),
        if (!_expanded && total > shown.length)
          textButton(
            'commentsShowAll',
            l.commentsShowAll(total),
            () => setState(() => _expanded = true),
          ),
        for (final c in shown)
          CommentRow(
            key: ValueKey('commentRow_${c.id}'),
            comment: c,
            canDelete: c.mine || (user?.isAdmin ?? false),
            canReport: !c.mine,
            onDelete: () => _delete(c),
            onReport: () => user == null ? _login() : _report(c),
          ),
        if (_expanded && thread.hasMore)
          thread.loadingMore
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : textButton(
                  'commentsLoadMore',
                  l.commentsLoadMore,
                  _thread.loadMore,
                ),
        if (_expanded && items.length > kCommentPreviewCount)
          textButton(
            'commentsShowLess',
            l.commentsShowLess,
            () => setState(() => _expanded = false),
          ),
        const SizedBox(height: 4),
        if (user == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('commentsLogin_$_id'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: small,
              ),
              onPressed: _login,
              icon: const Icon(Icons.chat_bubble_outline, size: 16),
              label: Text(l.commentLoginToWrite),
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('commentInput_$_id'),
                  controller: _text,
                  maxLines: 1,
                  maxLength: kCommentMaxLength,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _send(),
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: l.commentHint,
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: Key('commentSend_$_id'),
                tooltip: l.commentSend,
                visualDensity: VisualDensity.compact,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 20),
                onPressed: _sending || _text.text.trim().isEmpty ? null : _send,
              ),
            ],
          ),
      ],
    );
  }
}

/// One comment: the author's picture and name (both open their profile),
/// when, and the text. Its menu (also on long-press) deletes or reports it.
class CommentRow extends StatefulWidget {
  const CommentRow({
    super.key,
    required this.comment,
    required this.canDelete,
    required this.canReport,
    required this.onDelete,
    required this.onReport,
  });

  final Comment comment;
  final bool canDelete;
  final bool canReport;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  State<CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<CommentRow> {
  /// Long-press opens the same menu as the button.
  final _menu = GlobalKey<PopupMenuButtonState<String>>();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = widget.comment;
    final canDelete = widget.canDelete;
    final canReport = widget.canReport;
    final hasMenu = canDelete || canReport;
    final meta = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return InkWell(
      key: Key('comment_${c.id}'),
      borderRadius: BorderRadius.circular(12),
      onLongPress: hasMenu ? () => _menu.currentState?.showButtonMenu() : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AuthorAvatar(author: c.author, radius: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AuthorLink(
                          author: c.author,
                          style: meta?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Text(' · ${relativeTime(c.createdAt)}', style: meta),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(c.body),
                ],
              ),
            ),
            if (hasMenu)
              PopupMenuButton<String>(
                key: _menu,
                tooltip: l.commentMore,
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (v) =>
                    v == 'delete' ? widget.onDelete() : widget.onReport(),
                itemBuilder: (_) => [
                  if (canDelete)
                    PopupMenuItem(
                      key: Key('commentDelete_${c.id}'),
                      value: 'delete',
                      child: Text(l.commentDelete),
                    ),
                  if (canReport)
                    PopupMenuItem(
                      key: Key('commentReport_${c.id}'),
                      value: 'report',
                      child: Text(l.report),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the reason of a report; pops it (trimmed), or null on cancel.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  // owned here: it must outlive the dialog's closing animation
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.report),
      content: TextField(
        key: const Key('commentReportReason'),
        controller: _reason,
        decoration: InputDecoration(labelText: l.reportReason),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const Key('commentReportSend'),
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: Text(l.report),
        ),
      ],
    );
  }
}
