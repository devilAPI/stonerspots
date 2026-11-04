import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'data_export.dart';

/// Android and iOS: a temporary file handed to the share sheet, from which
/// the user saves it (Files, Drive, …) or sends it. Linux, Windows and
/// macOS (not sandboxed): the Downloads folder, without overwriting an
/// earlier export.
Future<ExportResult> saveExport(String name, String content) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        fileNameOverrides: [name],
      ),
    );
    return const ExportShared();
  }
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final file = freeFile(dir, name);
  await file.writeAsString(content, flush: true);
  return ExportSaved(file.path);
}

/// [name] in [dir], or `name-2.json`, `name-3.json` … when taken.
File freeFile(Directory dir, String name) {
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var file = File('${dir.path}${Platform.pathSeparator}$name');
  for (var i = 2; file.existsSync(); i++) {
    file = File('${dir.path}${Platform.pathSeparator}$stem-$i$ext');
  }
  return file;
}
