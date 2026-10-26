import 'dart:math';
import 'dart:typed_data';

import 'package:app/features/spots/image_compressor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Random pixels compress badly, so the encoded file is large.
img.Image _noise(int w, int h, {int channels = 3}) {
  final r = Random(1);
  final image = img.Image(width: w, height: h, numChannels: channels);
  for (final p in image) {
    p
      ..r = r.nextInt(256)
      ..g = r.nextInt(256)
      ..b = r.nextInt(256);
    if (channels == 4) p.a = 255;
  }
  return image;
}

/// Whether a JPEG carries an EXIF (APP1 "Exif") block.
bool _hasExif(Uint8List jpg) {
  const sig = [0x45, 0x78, 0x69, 0x66, 0, 0];
  for (var i = 0; i + sig.length <= jpg.length; i++) {
    var hit = true;
    for (var j = 0; j < sig.length && hit; j++) {
      hit = jpg[i + j] == sig[j];
    }
    if (hit) return true;
  }
  return false;
}

void main() {
  test('small files are uploaded unchanged', () async {
    final bytes = img.encodeJpg(_noise(100, 50));
    final out = await prepareForUpload(bytes);
    expect(out.compressed, isFalse);
    expect(identical(out.bytes, bytes), isTrue);
  });

  test('large photos are scaled to 2048 px and re-encoded as JPEG', () async {
    final image = _noise(3000, 1500, channels: 4);
    // a transparent corner, flattened onto white
    for (var y = 0; y < 100; y++) {
      for (var x = 0; x < 100; x++) {
        image.getPixel(x, y).a = 0;
      }
    }
    final bytes = img.encodePng(image);
    expect(bytes.length, greaterThan(kCompressAboveBytes));

    final out = await prepareForUpload(bytes);
    expect(out.compressed, isTrue);
    expect(out.bytes.length, lessThan(bytes.length));
    expect(out.bytes.length, lessThanOrEqualTo(kUploadMaxBytes));
    final decoded = img.decodeJpg(out.bytes)!;
    expect([decoded.width, decoded.height], [2048, 1024]);
    final corner = decoded.getPixel(10, 10);
    expect([corner.r, corner.g, corner.b], everyElement(greaterThan(240)));
  });

  test('EXIF orientation is applied and metadata dropped', () {
    final image = _noise(400, 200);
    image.exif.imageIfd.orientation = 6; // shot rotated 90° clockwise
    image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(48, 1);
    final bytes = img.encodeJpg(image, quality: 100);
    expect(_hasExif(bytes), isTrue);

    final out = compressImage(bytes)!;
    expect(_hasExif(out), isFalse); // no orientation, no GPS
    final decoded = img.decodeJpg(out)!;
    expect([decoded.width, decoded.height], [200, 400]); // upright
  });

  test('undecodable files are uploaded as they are', () async {
    final bytes = Uint8List(kCompressAboveBytes + 1);
    final out = await prepareForUpload(bytes);
    expect(out.compressed, isFalse);
    expect(identical(out.bytes, bytes), isTrue);
  });
}
