import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

class SpotPreviewSheet extends StatelessWidget {
  const SpotPreviewSheet({super.key, required this.spot, required this.onOpen});

  final Spot spot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cover = spot.coverUrl;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (cover != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(spot.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.favorite, size: 16),
              const SizedBox(width: 4),
              Text(l10n.likesCount(spot.likeCount)),
            ]),
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
