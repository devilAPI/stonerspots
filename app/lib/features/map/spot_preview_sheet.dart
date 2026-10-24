import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../spots/spot_media.dart';
import '../reviews/rating_widgets.dart';

class SpotPreviewSheet extends StatelessWidget {
  const SpotPreviewSheet({super.key, required this.spot, required this.onOpen});

  final Spot spot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cover = spot.coverUrl;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text(spot.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
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
