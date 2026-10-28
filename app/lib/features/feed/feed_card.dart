import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/net_photo.dart';
import '../../l10n/app_localizations.dart';
import '../reviews/rating_widgets.dart';
import 'satellite_thumb.dart';

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

/// How a [FeedCard] arranges picture and text.
enum FeedCardLayout {
  /// Picture above text (phone portrait list).
  stacked,

  /// Like [stacked], but fills the height its grid row gives it, with the
  /// likes pinned to the bottom so cards in a row line up.
  tile,

  /// Picture left of the text (phone landscape, where height is short).
  side,
}

class FeedCard extends StatelessWidget {
  const FeedCard({
    super.key,
    required this.item,
    this.layout = FeedCardLayout.stacked,
    this.margin = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final FeedItem item;
  final FeedCardLayout layout;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final media = item.photos.isEmpty
        ? SatelliteThumb(lat: item.spot.lat, lon: item.spot.lon)
        : AspectRatio(
            aspectRatio: 4 / 3,
            child: NetPhoto(
              item.photos.first.thumbUrl,
              placeholder: Colors.black12,
            ),
          );
    final text = _Text(item: item, fill: layout == FeedCardLayout.tile);
    return Card(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/spot/${item.spot.id}'),
        child: switch (layout) {
          FeedCardLayout.side => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 220, child: media),
              Expanded(child: text),
            ],
          ),
          FeedCardLayout.tile => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              media,
              Expanded(child: text),
            ],
          ),
          FeedCardLayout.stacked => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [media, text],
          ),
        },
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.item, required this.fill});

  final FeedItem item;

  /// Takes all the height it gets and pins the likes row to the bottom.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => context.push('/spot/${item.spot.id}'),
            child: Text(
              item.spot.title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${item.author.displayName} · '
                '${relativeTime(item.createdAt)}',
              ),
              if (item.updateCount > 1)
                InkWell(
                  key: const Key('feedUpdateCount'),
                  onTap: () => context.push('/spot/${item.spot.id}'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      '· ${l10n.feedUpdateCount(item.updateCount)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item.body, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          if (fill) const Spacer(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.favorite_border, size: 18),
              const SizedBox(width: 4),
              Text(l10n.likesCount(item.spot.likeCount)),
              const SizedBox(width: 12),
              RatingBadge(
                avg: item.spot.ratingAvg,
                count: item.spot.ratingCount,
                size: 16,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
