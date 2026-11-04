import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'data_export.dart';

/// The browser's own download of a file named [name].
Future<ExportResult> saveExport(String name, String content) async {
  final blob = web.Blob(
    <JSAny>[content.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  // the download has started by then; the URL only holds memory
  Future<void>.delayed(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return ExportDownloaded(name);
}
