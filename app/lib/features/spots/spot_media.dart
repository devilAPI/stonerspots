import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../feed/satellite_thumb.dart';

/// Keeps only absolute http(s) URLs. The API sends an empty `cover_url` for
/// spots nobody photographed, and image loading fails hard ("No host
/// specified") on empty or relative URLs.
List<String> validPhotoUrls(Iterable<String> urls) => [
  for (final u in urls)
    if (_isLoadable(u.trim())) u.trim(),
];

bool _isLoadable(String u) {
  final uri = Uri.tryParse(u);
  return uri != null &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

/// Horizontal strip with the user photos first and the top-down (satellite)
/// view of the spot as the last item.
class SpotMediaStrip extends StatelessWidget {
  const SpotMediaStrip({
    super.key,
    required this.photoUrls,
    required this.lat,
    required this.lon,
    this.height = 220,
    this.onPhotoTap,
  });

  final List<String> photoUrls;
  final double lat;
  final double lon;
  final double height;

  /// Receives the index within the valid photo URLs.
  final void Function(int index)? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final urls = validPhotoUrls(photoUrls);
    final width = height * 4 / 3;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: urls.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == urls.length) {
            return SizedBox(
              key: const Key('satelliteTile'),
              width: width,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SatelliteThumb(lat: lat, lon: lon),
              ),
            );
          }
          return InkWell(
            key: Key('galleryPhoto_$i'),
            borderRadius: BorderRadius.circular(8),
            onTap: onPhotoTap == null ? null : () => onPhotoTap!(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: width,
                child: CachedNetworkImage(
                  imageUrl: urls[i],
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
