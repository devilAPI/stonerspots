import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../map/map_tiles.dart';

/// One satellite tile placed inside a thumbnail of a given size.
class ThumbTile {
  const ThumbTile({
    required this.url,
    required this.left,
    required this.top,
    required this.size,
  });

  final String url;
  final double left;
  final double top;
  final double size;
}

/// The tiles (at most [kSatelliteMaxNativeZoom], scaled up beyond that) that
/// cover a [width] x [height] box centred on [lat]/[lon] at [zoom].
List<ThumbTile> satelliteThumbTiles({
  required double lat,
  required double lon,
  required double zoom,
  required double width,
  required double height,
}) {
  final z = math.min(zoom.floor(), kSatelliteMaxNativeZoom);
  final n = 1 << z;
  final tileSize = 256 * math.pow(2, zoom - z).toDouble();
  // Web Mercator position of the spot in tile units at zoom z.
  final latRad = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180;
  final tx = (lon + 180) / 360 * n;
  final ty =
      (1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n;
  final originX = tx * tileSize - width / 2;
  final originY = ty * tileSize - height / 2;
  final x0 = (originX / tileSize).floor();
  final x1 = ((originX + width) / tileSize).ceil() - 1;
  final y0 = math.max(0, (originY / tileSize).floor());
  final y1 = math.min(n - 1, ((originY + height) / tileSize).ceil() - 1);
  return [
    for (var y = y0; y <= y1; y++)
      for (var x = x0; x <= x1; x++)
        ThumbTile(
          url: satelliteTileUrl(z, x % n, y),
          left: x * tileSize - originX,
          top: y * tileSize - originY,
          size: tileSize,
        ),
  ];
}

/// Non-interactive top-down satellite picture of a spot, used where a post
/// has no photo of its own. Drawn from a few disk-cached tile images rather
/// than a full map widget, so long feeds scroll smoothly.
class SatelliteThumb extends StatelessWidget {
  const SatelliteThumb({
    super.key,
    required this.lat,
    required this.lon,
    this.zoom = 19,
  });

  final double lat;
  final double lon;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.black26,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              children: [
                for (final t in satelliteThumbTiles(
                  lat: lat,
                  lon: lon,
                  zoom: zoom,
                  width: c.maxWidth,
                  height: c.maxHeight,
                ))
                  Positioned(
                    left: t.left,
                    top: t.top,
                    width: t.size,
                    height: t.size,
                    child: Image(
                      image: CachedNetworkImageProvider(t.url),
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: kAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  right: 6,
                  bottom: 4,
                  child: Text(
                    'Esri World Imagery',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
