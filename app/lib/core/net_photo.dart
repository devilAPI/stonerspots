import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A disk-cached photo filling its box (cropped), with a broken-image icon
/// when it cannot be loaded.
///
/// [decodeWidth] (logical px) decodes the file at about that width instead
/// of its full size: a 1600 px photo in a small strip otherwise costs its
/// full size in memory and upload time on every scroll.
///
/// [fallback] replaces both the placeholder and the broken-image icon, e.g.
/// a user's initial while their picture loads or when it cannot.
class NetPhoto extends StatelessWidget {
  const NetPhoto(
    this.url, {
    super.key,
    this.decodeWidth,
    this.placeholder,
    this.fallback,
  });

  final String url;
  final double? decodeWidth;
  final Color? placeholder;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final w = decodeWidth;
    final placeholder = this.placeholder;
    final fallback = this.fallback;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: w == null
          ? null
          : (w * MediaQuery.devicePixelRatioOf(context)).round(),
      placeholder: fallback != null
          ? (_, _) => fallback
          : placeholder == null
          ? null
          : (_, _) => ColoredBox(color: placeholder),
      errorWidget: (_, _, _) =>
          fallback ?? const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}
