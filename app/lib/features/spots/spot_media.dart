import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
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

/// Item [index] of a spot's media: a user photo, or (after the photos) the
/// top-down view. Fills the size it is given.
class SpotMediaTile extends StatelessWidget {
  const SpotMediaTile({
    super.key,
    required this.photoUrls,
    required this.index,
    required this.lat,
    required this.lon,
    this.onPhotoTap,
    this.radius = 8,
  });

  final List<String> photoUrls;
  final int index;
  final double lat;
  final double lon;
  final void Function(int index)? onPhotoTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    if (index >= photoUrls.length) {
      return ClipRRect(
        key: const Key('satelliteTile'),
        borderRadius: shape,
        child: SatelliteThumb(lat: lat, lon: lon),
      );
    }
    return ClipRRect(
      borderRadius: shape,
      child: Material(
        key: Key('galleryPhoto_$index'),
        color: Colors.black12,
        child: InkWell(
          onTap: onPhotoTap == null ? null : () => onPhotoTap!(index),
          child: Ink.image(
            image: CachedNetworkImageProvider(photoUrls[index]),
            fit: BoxFit.cover,
            onImageError: (_, _) {},
          ),
        ),
      ),
    );
  }
}

/// Full-width swipeable pictures of a spot (photos, then the top-down view)
/// with a "2 / 5" counter. Mouse drag works too, for narrow desktop windows.
class SpotHeroCarousel extends StatefulWidget {
  const SpotHeroCarousel({
    super.key,
    required this.photoUrls,
    required this.lat,
    required this.lon,
    required this.height,
    this.onPhotoTap,
  });

  final List<String> photoUrls;
  final double lat;
  final double lon;
  final double height;
  final void Function(int index)? onPhotoTap;

  @override
  State<SpotHeroCarousel> createState() => _SpotHeroCarouselState();
}

class _SpotHeroCarouselState extends State<SpotHeroCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.photoUrls.length + 1;
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
            child: PageView.builder(
              key: const Key('spotCarousel'),
              controller: _controller,
              allowImplicitScrolling: true,
              itemCount: count,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (_, i) => SpotMediaTile(
                photoUrls: widget.photoUrls,
                index: i,
                lat: widget.lat,
                lon: widget.lon,
                onPhotoTap: widget.onPhotoTap,
                radius: 0,
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              left: 12,
              bottom: 10,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      '${_page + 1} / $count',
                      key: const Key('carouselCounter'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical gallery for a side pane: the first picture large, the others in
/// a grid below it (two columns when the pane is wide enough).
class SpotMediaGallery extends StatelessWidget {
  const SpotMediaGallery({
    super.key,
    required this.photoUrls,
    required this.lat,
    required this.lon,
    this.onPhotoTap,
  });

  final List<String> photoUrls;
  final double lat;
  final double lon;
  final void Function(int index)? onPhotoTap;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final count = photoUrls.length + 1;
      final columns = c.maxWidth >= 440 ? 2 : 1;
      final small = (c.maxWidth - _gap * (columns - 1)) / columns;
      Widget tile(int i, double width) => SizedBox(
        width: width,
        height: width * 3 / 4,
        child: SpotMediaTile(
          photoUrls: photoUrls,
          index: i,
          lat: lat,
          lon: lon,
          onPhotoTap: onPhotoTap,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tile(0, c.maxWidth),
          if (count > 1) ...[
            const SizedBox(height: _gap),
            Wrap(
              spacing: _gap,
              runSpacing: _gap,
              children: [for (var i = 1; i < count; i++) tile(i, small)],
            ),
          ],
        ],
      );
    },
  );
}
