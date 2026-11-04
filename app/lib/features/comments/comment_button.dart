import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart' show FeedItem;
import '../../l10n/app_localizations.dart';
import 'comments_controller.dart';
import 'comments_sheet.dart';

/// Speech bubble with the update's comment count; opens its thread.
class CommentButton extends ConsumerWidget {
  const CommentButton({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final count = CommentCounts.of(ref.watch(commentCountsProvider), item);
    return Tooltip(
      message: l.commentsTitle,
      child: InkWell(
        key: Key('commentButton_${item.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => showCommentsSheet(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 18),
              const SizedBox(width: 4),
              Text('$count', key: Key('commentCount_${item.id}')),
            ],
          ),
        ),
      ),
    );
  }
}
