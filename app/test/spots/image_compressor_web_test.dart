@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:app/features/spots/browser_image_codec_web.dart';
import 'package:app/features/spots/image_compressor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;

/// A w x h PNG of random pixels (large on disk), drawn by the browser
/// because the Dart encoder is very slow when compiled to JS.
Future<Uint8List> _noisePng(int w, int h) async {
  final canvas = web.HTMLCanvasElement()
    ..width = w
    ..height = h;
  final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
  final data = ctx.createImageData(w.toJS, h);
  final px = data.data.toDart;
  final r = Random(1);
  for (var i = 0; i < px.length; i++) {
    px[i] = i % 4 == 3 ? 255 : r.nextInt(256);
  }
  ctx.putImageData(data, 0, 0);
  final done = Completer<web.Blob>();
  canvas.toBlob(((web.Blob b) => done.complete(b)).toJS, 'image/png');
  final blob = await done.future;
  return (await blob.arrayBuffer().toDart).toDart.asUint8List();
}

void main() {
  test('large photos are compressed quickly by the browser', () async {
    final bytes = await _noisePng(3000, 1500);
    expect(bytes.length, greaterThan(kCompressAboveBytes));

    final sw = Stopwatch()..start();
    final out = await prepareForUpload(bytes);
    // ignore: avoid_print
    print(
      'browser: ${bytes.length ~/ 1024} KB -> '
      '${out.bytes.length ~/ 1024} KB in ${sw.elapsedMilliseconds} ms',
    );
    expect(out.compressed, isTrue);
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    expect(out.bytes.length, lessThanOrEqualTo(kUploadMaxBytes));
    final info = img.JpegDecoder().startDecode(out.bytes)!;
    expect([info.width, info.height], [2048, 1024]);
  });

  test('EXIF orientation is applied and metadata dropped', () async {
    final image = img.Image(width: 40, height: 20);
    image.exif.imageIfd.orientation = 6; // shot rotated 90° clockwise
    final bytes = img.encodeJpg(image);

    final out = (await compressInBrowser(
      bytes,
      maxEdge: 2048,
      maxPixels: 40000000,
      maxBytes: kUploadMaxBytes,
      qualities: const [85],
    ))!;
    final info = img.JpegDecoder().startDecode(out)!;
    expect([info.width, info.height], [20, 40]); // upright
    expect(String.fromCharCodes(out).contains('Exif'), isFalse);
  });

  test('undecodable files are uploaded as they are', () async {
    final bytes = Uint8List(kCompressAboveBytes + 1);
    final out = await prepareForUpload(bytes);
    expect(out.compressed, isFalse);
    expect(identical(out.bytes, bytes), isTrue);
  });
}
