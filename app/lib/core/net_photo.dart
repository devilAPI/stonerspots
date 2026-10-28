import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A disk-cached photo filling its box (cropped), with a broken-image icon
/// when it cannot be loaded.
///
/// [decodeWidth] (logical px) decodes the file at about that width instead
/// of its full size: a 1600 px photo in a small strip otherwise costs its
/// full size in memory and upload time on every scroll.
class NetPhoto extends StatelessWidget {
  const NetPhoto(this.url, {super.key, this.decodeWidth, this.placeholder});

  final String url;
  final double? decodeWidth;
  final Color? placeholder;

  @override
  Widget build(BuildContext context) {
    final w = decodeWidth;
    final placeholder = this.placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: w == null
          ? null
          : (w * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: placeholder == null
          ? null
          : (_, _) => ColoredBox(color: placeholder),
      errorWidget: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
