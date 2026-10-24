import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../feed/satellite_thumb.dart';
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
            // User photos first; a spot nobody photographed yet is shown
            // from above instead.
            Center(
              child: ConstrainedBox(
                // landscape phones are short: keep the title and button visible
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: cover != null
                      ? AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: cover,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                const Center(child: Icon(Icons.broken_image)),
                          ),
                        )
                      : SatelliteThumb(lat: spot.lat, lon: spot.lon),
                ),
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
