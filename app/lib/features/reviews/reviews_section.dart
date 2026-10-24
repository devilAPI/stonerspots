import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart' show relativeTime;
import 'rating_widgets.dart';
import 'review_dialog.dart';
import 'review_models.dart';
import 'reviews_repository.dart';

/// Rating summary, "write a review" button and the paged review list of a
/// spot.
class ReviewsSection extends ConsumerStatefulWidget {
  const ReviewsSection({
    super.key,
    required this.spotId,
    required this.gate,
    required this.onReport,
    this.onChanged,
  });

  final int spotId;

  /// Runs the action only for logged-in users (otherwise goes to login).
  final void Function(VoidCallback action) gate;
  final void Function(int reviewId) onReport;

  /// Called after the user saved or deleted their review.
  final VoidCallback? onChanged;

  @override
  ConsumerState<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends ConsumerState<ReviewsSection> {
  ReviewSummary _summary = ReviewSummary.empty;
  Review? _mine;
  List<Review> _items = const [];
  String? _next;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  ReviewsRepository get _repo => ref.read(reviewsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await _repo.list(widget.spotId);
      if (!mounted) return;
      setState(() {
        _summary = page.summary;
        _mine = page.mine;
        _items = page.items;
        _next = page.nextCursor;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_next == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.list(widget.spotId, cursor: _next);
      if (!mounted) return;
      setState(() {
        _summary = page.summary;
        _items = [..._items, ...page.items];
        _next = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
        _snack(AppLocalizations.of(context).errorGeneric);
      }
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _write() async {
    final saved = await showReviewDialog(
      context,
      existing: _mine,
      onSave: (rating, body) async {
        await _repo.save(widget.spotId, rating, body);
      },
    );
    if (saved == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.reviewDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('reviewDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.reviewDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(widget.spotId);
    } catch (_) {
      if (mounted) _snack(l.errorGeneric);
      return;
    }
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final myId = ref.watch(authControllerProvider).value?.id;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.reviewsTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_failed)
            Row(
              children: [
                Text(l.errorGeneric),
                TextButton(
                  onPressed: () {
                    setState(() => _loading = true);
                    _load();
                  },
                  child: Text(l.retry),
                ),
              ],
            )
          else ...[
            _SummaryView(summary: _summary),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('writeReview'),
              onPressed: () => widget.gate(_write),
              icon: const Icon(Icons.rate_review_outlined),
              label: Text(_mine == null ? l.reviewWrite : l.reviewEditMine),
            ),
            const SizedBox(height: 8),
            for (final r in _items)
              _ReviewTile(
                review: r,
                isMine: myId != null && r.author.id == myId,
                onEdit: () => widget.gate(_write),
                onDelete: _delete,
                onReport: () => widget.gate(() => widget.onReport(r.id)),
              ),
            if (_next != null)
              Center(
                child: TextButton(
                  key: const Key('reviewMore'),
                  onPressed: _loadingMore ? null : _loadMore,
                  child: _loadingMore
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.reviewLoadMore),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (summary.count == 0) {
      return Row(
        key: const Key('reviewSummary'),
        children: [
          const StarRow(rating: 0, size: 22),
          const SizedBox(width: 12),
          Flexible(child: Text(l.reviewNone)),
        ],
      );
    }
    final maxCount = summary.distribution.values.fold<int>(
      1,
      (a, b) => b > a ? b : a,
    );
    return Row(
      key: const Key('reviewSummary'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              formatRating(summary.avg),
              style: theme.textTheme.displaySmall,
            ),
            StarRow(rating: summary.avg, size: 16),
            const SizedBox(height: 2),
            Text(
              l.reviewCount(summary.count),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        child: Text('$star', style: theme.textTheme.bodySmall),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            key: Key('reviewDistBar_$star'),
                            minHeight: 8,
                            value: (summary.distribution[star] ?? 0) / maxCount,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
  });

  final Review review;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta =
        StringBuffer(isMine ? l.reviewYours : review.author.displayName)
          ..write(' · ')
          ..write(relativeTime(review.createdAt));
    if (review.isEdited) meta.write(' · ${l.reviewEdited}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarRow(rating: review.rating.toDouble(), size: 16),
                const SizedBox(height: 2),
                Text(meta.toString(), style: theme.textTheme.bodySmall),
                if (review.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(review.body),
                ],
              ],
            ),
          ),
          if (isMine) ...[
            IconButton(
              key: Key('reviewEdit_${review.id}'),
              tooltip: l.reviewActionEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
            IconButton(
              key: Key('reviewDelete_${review.id}'),
              tooltip: l.reviewActionDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ] else
            IconButton(
              key: Key('reviewReport_${review.id}'),
              tooltip: l.report,
              icon: const Icon(Icons.flag_outlined),
              onPressed: onReport,
            ),
        ],
      ),
    );
  }
}
