import 'dart:typed_data';

/// Outside the browser there is no native codec to use; see
/// browser_image_codec_web.dart.
Future<Uint8List?> compressInBrowser(
  Uint8List bytes, {
  required int maxEdge,
  required int maxPixels,
  required int maxBytes,
  required List<int> qualities,
}) async => null;
