import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../l10n/app_localizations.dart';
import 'export_saver_io.dart'
    if (dart.library.js_interop) 'export_saver_web.dart'
    as platform;

/// What became of the downloaded data.
sealed class ExportResult {
  const ExportResult();
}

/// Written to a file (desktop): [path].
class ExportSaved extends ExportResult {
  const ExportSaved(this.path);
  final String path;
}

/// Handed to the browser as a download named [name] (web).
class ExportDownloaded extends ExportResult {
  const ExportDownloaded(this.name);
  final String name;
}

/// Handed to the system share sheet (Android, iOS), which shows itself.
class ExportShared extends ExportResult {
  const ExportShared();
}

/// Puts [content] where the user can keep it, as a file named [name]: the
/// browser's download (web), the share sheet (Android, iOS; "save to
/// files", Drive, mail …) or the Downloads folder (Linux, Windows, macOS).
typedef ExportSaver = Future<ExportResult> Function(
  String name,
  String content,
);

final exportSaverProvider = Provider<ExportSaver>((ref) => platform.saveExport);

/// `GET /me/export`: everything the server stores about the caller.
abstract class DataExportRepository {
  /// The document as pretty-printed JSON.
  Future<String> fetch();
}

class ApiDataExportRepository implements DataExportRepository {
  ApiDataExportRepository(this._api);

  final ApiClient _api;

  @override
  Future<String> fetch() async {
    final doc = await _api.get<Object?>(
      '/me/export',
      receiveTimeout: const Duration(minutes: 2),
    );
    return '${const JsonEncoder.withIndent('  ').convert(doc)}\n';
  }
}

final dataExportRepositoryProvider = Provider<DataExportRepository>(
  (ref) => ApiDataExportRepository(ref.watch(apiClientProvider)),
);

/// `stonerspots-export-2026-11-04.json`.
String exportFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'stonerspots-export-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

/// "Meine Daten herunterladen": fetches the export and saves it, telling
/// the user in a snack bar how it went.
Future<void> downloadMyData(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  say(l10n.exportPreparing);
  try {
    final json = await ref.read(dataExportRepositoryProvider).fetch();
    final result = await ref.read(exportSaverProvider)(
      exportFileName(DateTime.now()),
      json,
    );
    switch (result) {
      case ExportSaved(:final path):
        say(l10n.exportSaved(path));
      case ExportDownloaded(:final name):
        say(l10n.exportDownloaded(name));
      case ExportShared():
        messenger.hideCurrentSnackBar();
    }
  } on ApiException catch (e) {
    say(e.status == 429 ? l10n.exportRateLimited : l10n.exportFailed);
  } catch (_) {
    say(l10n.exportFailed);
  }
}
