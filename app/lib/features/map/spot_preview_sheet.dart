import 'package:flutter/material.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../saved/save_spot_button.dart';
import '../spots/spot_media.dart';
import '../reviews/rating_widgets.dart';
import '../users/author_link.dart';

class SpotPreviewSheet extends StatelessWidget {
  const SpotPreviewSheet({
    super.key,
    required this.spot,
    required this.onOpen,
    this.scrollController,
    this.header,
    this.onOpenAuthor,
  });

  final Spot spot;
  final VoidCallback onOpen;

  /// Opens the owner's profile (e.g. after closing the sheet); by default
  /// it is pushed.
  final void Function(int userId)? onOpenAuthor;

  /// Set inside a draggable sheet: drags on the card then move the sheet.
  final ScrollController? scrollController;

  /// Shown above the content, scrolling with it.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cover = spot.coverUrl;
    return SafeArea(
      child: SingleChildScrollView(
        controller: scrollController,
        physics: scrollController == null
            ? null
            : const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?header,
            // User photos first, then the spot seen from above.
            SpotMediaStrip(
              photoUrls: [?cover],
              lat: spot.lat,
              lon: spot.lon,
              // landscape phones are short: keep the title and button visible
              height: (MediaQuery.sizeOf(context).height * 0.3).clamp(
                110.0,
                180.0,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    spot.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                // the card sits on glass
                SaveSpotButton(
                  spotId: spot.id,
                  iconOnly: true,
                  color: kOnGlass,
                ),
              ],
            ),
            const SizedBox(height: 2),
            SpotOwnerLine(
              author: spot.author,
              avatarRadius: 10,
              style: Theme.of(context).textTheme.bodySmall,
              onTap: onOpenAuthor,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.favorite, size: 16),
                const SizedBox(width: 4),
                Text(l10n.likesCount(spot.likeCount)),
                const SizedBox(width: 12),
                RatingBadge(avg: spot.ratingAvg, count: spot.ratingCount),
              ],
            ),
            if (spot.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              SpotTagChips(
                tags: spot.tags,
                keyPrefix: 'previewTag-',
                compact: true,
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onOpen,
                child: Text(l10n.openSpot),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
