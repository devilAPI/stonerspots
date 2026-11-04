import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/glass.dart';
import '../../core/models.dart' show FeedItem;
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart' show relativeTime;
import '../spots/spot_api.dart';
import 'comment_models.dart';
import 'comments_controller.dart';

/// Opens the comment thread of [item] in a glass sheet. Logged-out users who
/// want to write are sent to the login page, like for likes.
Future<void> showCommentsSheet(BuildContext context, FeedItem item) {
  final router = GoRouter.maybeOf(context);
  return showGlassSheet<void>(
    context: context,
    radius: 32,
    // above the shell's floating tab bar
    useRootNavigator: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => CommentsSheet(
      updateId: item.id,
      baseCount: item.commentCount,
      onLogin: () {
        Navigator.of(sheetContext).pop();
        // pushed: after logging in it pops back to where the user was
        router?.push('/login');
      },
    ),
  );
}

/// The thread of one update with a composer below it.
class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    super.key,
    required this.updateId,
    required this.baseCount,
    required this.onLogin,
  });

  final int updateId;

  /// The comment count the update came with (see [CommentCounts]).
  final int baseCount;
  final VoidCallback onLogin;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _text = TextEditingController();
  bool _sending = false;

  /// Shown inside the sheet: a snackbar would sit behind it.
  String? _notice;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    Future.microtask(() {
      if (mounted) _thread.load();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  CommentThreadController get _thread =>
      ref.read(commentThreadProvider(widget.updateId).notifier);

  void _counted(int delta) => ref
      .read(commentCountsProvider.notifier)
      .adjust(widget.updateId, widget.baseCount, delta);

  String _errorText(AppLocalizations l, Object e) => switch (e) {
    ApiException(status: 429) => l.commentsQuota,
    ApiException(status: 404) => l.commentsGone,
    _ => l.errorGeneric,
  };

  Future<void> _send() async {
    final l = AppLocalizations.of(context);
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _notice = null;
    });
    try {
      await _thread.post(body);
      _counted(1);
      _text.clear();
    } catch (e) {
      if (mounted) setState(() => _notice = _errorText(l, e));
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
    setState(() => _notice = null);
    try {
      await _thread.delete(c);
      _counted(-1);
    } catch (e) {
      if (mounted) setState(() => _notice = _errorText(l, e));
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
      if (mounted) setState(() => _notice = l.commentReported);
    } catch (e) {
      if (mounted) setState(() => _notice = _errorText(l, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final thread = ref.watch(commentThreadProvider(widget.updateId));
    final user = ref.watch(authControllerProvider).value;

    final Widget list;
    if (thread.items.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: !thread.loadedOnce || thread.loading
              ? const CircularProgressIndicator()
              : thread.error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_errorText(l, thread.error!)),
                    TextButton(
                      key: const Key('commentsRetry'),
                      onPressed: _thread.load,
                      child: Text(l.retry),
                    ),
                  ],
                )
              : Text(l.commentsEmpty, textAlign: TextAlign.center),
        ),
      );
    } else {
      final extra = thread.hasMore || thread.loadingMore ? 1 : 0;
      list = ListView.builder(
        key: const Key('commentsList'),
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: thread.items.length + extra,
        itemBuilder: (_, i) {
          if (i == thread.items.length) {
            return Center(
              child: thread.loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    )
                  : TextButton(
                      key: const Key('commentsLoadMore'),
                      onPressed: _thread.loadMore,
                      child: Text(l.commentsLoadMore),
                    ),
            );
          }
          final c = thread.items[i];
          return _CommentRow(
            comment: c,
            canDelete: c.mine || (user?.isAdmin ?? false),
            canReport: !c.mine,
            onDelete: () => _delete(c),
            onReport: () => user == null ? widget.onLogin() : _report(c),
          );
        },
      );
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(l.commentsTitle, style: theme.textTheme.titleMedium),
            ),
            Flexible(child: list),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(
                  _notice!,
                  key: const Key('commentsNotice'),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: user == null
                  ? FilledButton.tonal(
                      key: const Key('commentsLogin'),
                      onPressed: widget.onLogin,
                      child: Text(l.commentLoginToWrite),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('commentInput'),
                            controller: _text,
                            minLines: 1,
                            maxLines: 4,
                            maxLength: kCommentMaxLength,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: l.commentHint,
                              counterText: '',
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0x24FFFFFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          key: const Key('commentSend'),
                          tooltip: l.commentSend,
                          icon: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                          onPressed: _sending || _text.text.trim().isEmpty
                              ? null
                              : _send,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatefulWidget {
  const _CommentRow({
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
  State<_CommentRow> createState() => _CommentRowState();
}

class _CommentRowState extends State<_CommentRow> {
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
    return InkWell(
      key: Key('comment_${c.id}'),
      borderRadius: BorderRadius.circular(12),
      onLongPress: hasMenu ? () => _menu.currentState?.showButtonMenu() : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.author.displayName} · ${relativeTime(c.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kOnGlass.withValues(alpha: 0.7),
                    ),
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
              )
            else
              const SizedBox(width: 12),
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
