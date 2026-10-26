import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Files at or below this size are uploaded as they are.
const kCompressAboveBytes = 1536 * 1024;

/// Long edge of a compressed photo. Above the server's 1600 px, so the
/// server still does the final, high-quality resize.
const kCompressMaxEdge = 2048;

/// The server's upload limit; compression lowers the quality until the
/// result fits.
const kUploadMaxBytes = 8 << 20;

/// Images with more pixels are not decoded on the device (memory); the
/// server rejects them anyway.
const _maxPixels = 40000000;

const _qualities = [85, 75, 65, 50];

/// A photo ready for upload: compressed, or the original when that was
/// smaller or could not be decoded.
class PreparedPhoto {
  const PreparedPhoto(this.bytes, {required this.compressed});

  final Uint8List bytes;

  /// The bytes are a newly encoded JPEG.
  final bool compressed;
}

/// Shrinks a photo over [kCompressAboveBytes]: applies its EXIF
/// orientation, scales the long edge down to [kCompressMaxEdge] and
/// re-encodes it as JPEG without metadata (no GPS leaves the device). Runs
/// in a background isolate where the platform has them.
Future<PreparedPhoto> prepareForUpload(Uint8List bytes) async {
  if (bytes.length <= kCompressAboveBytes) {
    return PreparedPhoto(bytes, compressed: false);
  }
  final out = await compute(compressImage, bytes);
  return out == null
      ? PreparedPhoto(bytes, compressed: false)
      : PreparedPhoto(out, compressed: true);
}

/// The compression itself; null when the original should be kept: not a
/// format the device can decode (e.g. AVIF), too many pixels, or nothing
/// gained.
@visibleForTesting
Uint8List? compressImage(Uint8List bytes) {
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null ||
      info == null ||
      info.width * info.height > _maxPixels) {
    return null;
  }
  final decoded = decoder.decode(bytes, frame: 0);
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);
  final long = math.max(image.width, image.height);
  if (long > kCompressMaxEdge) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: kCompressMaxEdge,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: kCompressMaxEdge,
            interpolation: img.Interpolation.average,
          );
  }
  if (image.hasAlpha || image.hasPalette) {
    // JPEG has no alpha: flatten onto white, like the server does.
    final flat = img.Image(width: image.width, height: image.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(flat, image);
  }
  image.exif = img.ExifData();

  Uint8List? out;
  for (final q in _qualities) {
    out = img.encodeJpg(image, quality: q);
    if (out.length <= kUploadMaxBytes) break;
  }
  return out != null && out.length < bytes.length ? out : null;
}
