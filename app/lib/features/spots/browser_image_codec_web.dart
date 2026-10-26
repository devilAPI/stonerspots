import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Compresses with the browser's own decoder and JPEG encoder, which are
/// native and fast; the pure-Dart codec compiled to JS takes over a minute
/// for a phone photo and blocks the page meanwhile. createImageBitmap
/// applies the EXIF orientation and the canvas output carries no metadata.
/// Null when the browser can't decode the file or it has too many pixels.
Future<Uint8List?> compressInBrowser(
  Uint8List bytes, {
  required int maxEdge,
  required int maxPixels,
  required int maxBytes,
  required List<int> qualities,
}) async {
  final web.ImageBitmap bitmap;
  try {
    bitmap = await web.window
        .createImageBitmap(web.Blob([bytes.toJS].toJS))
        .toDart;
  } catch (_) {
    return null;
  }
  try {
    final w = bitmap.width, h = bitmap.height;
    if (w <= 0 || h <= 0 || w * h > maxPixels) return null;
    final scale = math.min(1.0, maxEdge / math.max(w, h));
    final cw = math.max(1, (w * scale).round());
    final ch = math.max(1, (h * scale).round());
    final canvas = web.HTMLCanvasElement()
      ..width = cw
      ..height = ch;
    final ctx = canvas.getContext('2d')! as web.CanvasRenderingContext2D;
    // JPEG has no alpha: flatten onto white, like the server does.
    ctx
      ..fillStyle = 'white'.toJS
      ..fillRect(0, 0, cw, ch)
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high'
      ..drawImage(bitmap, 0, 0, cw, ch);
    Uint8List? out;
    for (final q in qualities) {
      out = await _toJpeg(canvas, q / 100);
      if (out == null || out.length <= maxBytes) break;
    }
    return out;
  } finally {
    bitmap.close();
  }
}

Future<Uint8List?> _toJpeg(web.HTMLCanvasElement canvas, double quality) {
  final done = Completer<web.Blob?>();
  canvas.toBlob(
    ((web.Blob? b) => done.complete(b)).toJS,
    'image/jpeg',
    quality.toJS,
  );
  return done.future.then(
    (b) async =>
        b == null ? null : (await b.arrayBuffer().toDart).toDart.asUint8List(),
  );
}
