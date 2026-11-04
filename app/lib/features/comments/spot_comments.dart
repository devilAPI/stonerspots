import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart' show relativeTime;
import '../spots/spot_api.dart';
import '../users/author_link.dart';
import 'comment_models.dart';
import 'comments_controller.dart';

/// How many of the newest comments show while the section is collapsed.
const kCommentPreviewCount = 3;

/// The comments section of a spot page, styled like its reviews and
/// updates: a heading, a one-line composer (logged out: a login button;
/// on a locked spot only admins may write), then the newest
/// [kCommentPreviewCount] comments and a button that shows all of them,
/// paging through older ones.
class SpotComments extends ConsumerStatefulWidget {
  const SpotComments({
    super.key,
    required this.spotId,
    required this.count,
    this.canWrite = true,
  });

  final int spotId;

  /// How many comments the spot had when it was loaded.
  final int count;

  /// False on a locked spot for non-admins: no composer.
  final bool canWrite;

  @override
  ConsumerState<SpotComments> createState() => _SpotCommentsState();
}

class _SpotCommentsState extends ConsumerState<SpotComments>
    with AutomaticKeepAliveClientMixin {
  /// The page is a lazy list: scrolled away and back, the section keeps
  /// its comments, a half-written one and what is expanded, instead of
  /// loading again.
  @override
  bool get wantKeepAlive => true;

  final _text = TextEditingController();
  bool _expanded = false;
  bool _sending = false;

  /// Comments posted (+) and deleted (-) here since [SpotComments.count]
  /// came from the server.
  int _delta = 0;

  SpotCommentsController get _comments =>
      ref.read(spotCommentsProvider(widget.spotId).notifier);

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    // Nothing to fetch for a spot without comments.
    if (widget.count > 0) {
      Future.microtask(() {
        if (mounted) _comments.load();
      });
    }
  }

  @override
  void didUpdateWidget(SpotComments old) {
    super.didUpdateWidget(old);
    // a reloaded spot brings a count that already has our changes
    if (old.count != widget.count) _delta = 0;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String _errorText(AppLocalizations l, Object e, {bool posting = false}) =>
      switch (e) {
        ApiException(status: 429) => l.commentsQuota,
        ApiException(status: 403) => l.commentsLocked,
        ApiException(status: 404) =>
          posting ? l.commentsSpotGone : l.commentGone,
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
      await _comments.post(body);
      _delta++;
      _text.clear();
    } catch (e) {
      if (mounted) _snack(_errorText(l, e, posting: true));
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
      await _comments.delete(c);
      if (mounted) setState(() => _delta--);
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
    super.build(context);
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final comments = ref.watch(spotCommentsProvider(widget.spotId));
    final user = ref.watch(authControllerProvider).value;
    final items = comments.items;

    final shown = _expanded || items.length <= kCommentPreviewCount
        ? items
        : items.sublist(0, kCommentPreviewCount);
    final counted = widget.count + _delta;
    final total = counted > items.length ? counted : items.length;
    final small = theme.textTheme.labelLarge;

    Widget textButton(Key key, String label, VoidCallback onPressed) => Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: key,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: small,
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );

    final Widget composer;
    if (user == null) {
      composer = OutlinedButton.icon(
        key: const Key('commentsLogin'),
        onPressed: _login,
        icon: const Icon(Icons.chat_bubble_outline),
        label: Text(l.commentLoginToWrite),
      );
    } else if (!widget.canWrite) {
      composer = Text(
        l.commentsLocked,
        key: const Key('commentsLocked'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    } else {
      composer = Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('commentInput'),
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
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
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
            key: const Key('commentSend'),
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
      );
    }

    return Padding(
      key: const Key('spotComments'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.commentsTitle,
            key: const Key('commentsHeading'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          composer,
          const SizedBox(height: 8),
          if (items.isEmpty &&
              (comments.loading || (widget.count > 0 && !comments.loadedOnce)))
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (items.isEmpty && comments.error != null)
            Row(
              children: [
                Flexible(child: Text(l.errorGeneric)),
                TextButton(
                  key: const Key('commentsRetry'),
                  onPressed: _comments.load,
                  child: Text(l.retry),
                ),
              ],
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.commentsEmpty, key: const Key('commentsEmpty')),
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
          if (!_expanded && total > shown.length)
            textButton(
              const Key('commentsShowAll'),
              l.commentsShowAll(total),
              () => setState(() => _expanded = true),
            ),
          if (_expanded && comments.hasMore)
            comments.loadingMore
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
                    const Key('commentsLoadMore'),
                    l.commentsLoadMore,
                    _comments.loadMore,
                  ),
          if (_expanded && items.length > kCommentPreviewCount)
            textButton(
              const Key('commentsShowLess'),
              l.commentsShowLess,
              () => setState(() => _expanded = false),
            ),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AuthorAvatar(author: c.author, radius: 16),
            ),
            const SizedBox(width: 12),
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
