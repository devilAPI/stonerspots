import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

/// Language-neutral compact relative time: now, 5m, 3h, 2d, 4w, 1y.
String relativeTime(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 365) return '${d.inDays ~/ 7}w';
  return '${d.inDays ~/ 365}y';
}

class FeedCard extends StatelessWidget {
  const FeedCard({super.key, required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.photos.isNotEmpty)
            AspectRatio(
              aspectRatio: 4 / 3,
              child: CachedNetworkImage(
                imageUrl: item.photos.first.thumbUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => const ColoredBox(color: Colors.black12),
                errorWidget: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.push('/spot/${item.spot.id}'),
                  child: Text(
                    item.spot.title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.author.displayName} · '
                  '${relativeTime(item.createdAt)}',
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(item.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.favorite_border, size: 18),
                    const SizedBox(width: 4),
                    Text(l10n.likesCount(item.spot.likeCount)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
