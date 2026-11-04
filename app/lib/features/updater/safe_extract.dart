import 'dart:io';

import 'package:archive/archive_io.dart';

/// The archive tries to write outside its folder, links where it must not,
/// or is not an archive at all.
class UnsafeArchiveException implements Exception {
  const UnsafeArchiveException(this.message);

  final String message;

  @override
  String toString() => 'UnsafeArchiveException: $message';
}

/// Marks files executable after extraction (POSIX only).
typedef MakeExecutable = Future<void> Function(List<String> paths);

Future<void> _chmodExecutable(List<String> paths) async {
  for (var i = 0; i < paths.length; i += 200) {
    final batch = paths.sublist(i, (i + 200).clamp(0, paths.length));
    final r = await Process.run('chmod', ['755', '--', ...batch]);
    if (r.exitCode != 0) {
      throw UnsafeArchiveException('chmod failed: ${r.stderr}');
    }
  }
}

/// The path segments of an archive entry name, or an exception when the
/// name could point anywhere but below the extraction folder.
List<String> safeEntrySegments(String name) {
  if (name.contains('\u0000')) {
    throw UnsafeArchiveException('NUL in entry name: $name');
  }
  // Windows reads a backslash as a separator, so it counts as one here.
  final unified = name.replaceAll('\\', '/');
  if (unified.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
    throw UnsafeArchiveException('absolute entry name: $name');
  }
  final out = <String>[];
  for (final s in unified.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') throw UnsafeArchiveException('".." in entry name: $name');
    // drive-relative names and NTFS alternate data streams
    if (s.contains(':')) throw UnsafeArchiveException('":" in entry: $name');
    out.add(s);
  }
  return out;
}

class _Entry {
  _Entry(this.file, this.segments);

  final ArchiveFile file;
  final List<String> segments;

  String get key => segments.join('/');
}

/// Where symlink [linkKey] (archive-relative, `/`-separated) points, fully
/// resolved through the other links in [links] as the file system would.
/// Throws when it leaves the archive's folder or loops.
List<String> _resolveLink(String linkKey, Map<String, String> links) {
  var hops = 0;
  List<String> resolve(List<String> path) {
    final out = <String>[];
    final queue = [...path];
    while (queue.isNotEmpty) {
      final s = queue.removeAt(0);
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (out.isEmpty) {
          throw UnsafeArchiveException('link $linkKey points outside');
        }
        out.removeLast();
        continue;
      }
      out.add(s);
      final target = links[out.join('/')];
      if (target != null) {
        if (++hops > 40) throw UnsafeArchiveException('link loop at $linkKey');
        out.removeLast();
        queue.insertAll(0, _linkTarget(target));
      }
    }
    return out;
  }

  final segs = linkKey.split('/');
  return resolve([
    ...segs.sublist(0, segs.length - 1),
    ..._linkTarget(links[linkKey]!),
  ]);
}

/// The segments of a link target; only plain relative targets are allowed.
List<String> _linkTarget(String target) {
  if (target.isEmpty ||
      target.startsWith('/') ||
      target.contains('\\') ||
      target.contains('\u0000') ||
      RegExp(r'^[A-Za-z]:').hasMatch(target)) {
    throw UnsafeArchiveException('link target not allowed: $target');
  }
  return target.split('/');
}

/// Unpacks [archive] into [dest], which must not exist yet. Before anything
/// is written, every entry is checked: no absolute names, no `..`, no hard
/// links, symbolic links only when [allowSymlinks] and only to places
/// inside [dest] (followed through other links), no entry below a link, no
/// name twice, and at most [maxTotalBytes] in all.
///
/// Files that are executable in the archive get mode 755 on POSIX systems.
Future<void> extractArchiveSafely(
  Archive archive,
  Directory dest, {
  bool allowSymlinks = false,
  int maxTotalBytes = 1 << 30,
  int maxEntries = 50000,
  MakeExecutable? makeExecutable,
}) async {
  if (dest.existsSync()) {
    throw UnsafeArchiveException('${dest.path} already exists');
  }
  final entries = <_Entry>[];
  final links = <String, String>{};
  final seen = <String>{};
  var total = 0;
  if (archive.length > maxEntries) {
    throw const UnsafeArchiveException('too many entries');
  }
  for (final f in archive) {
    final segments = safeEntrySegments(f.name);
    if (segments.isEmpty) continue; // "./"
    final e = _Entry(f, segments);
    if (!seen.add(e.key)) {
      throw UnsafeArchiveException('${e.key} appears twice');
    }
    if (f.isHardLink) {
      throw UnsafeArchiveException('hard link ${e.key}');
    }
    if (f.isSymbolicLink) {
      if (!allowSymlinks) {
        throw UnsafeArchiveException('symbolic link ${e.key}');
      }
      links[e.key] = f.symbolicLink!;
    } else if (f.isFile) {
      total += f.size;
      if (total > maxTotalBytes) {
        throw const UnsafeArchiveException('archive unpacks too large');
      }
    }
    entries.add(e);
  }
  for (final e in entries) {
    // nothing may be written through a link
    for (var i = 1; i < e.segments.length; i++) {
      final parent = e.segments.sublist(0, i).join('/');
      if (links.containsKey(parent)) {
        throw UnsafeArchiveException('${e.key} lies below the link $parent');
      }
    }
    if (links.containsKey(e.key)) _resolveLink(e.key, links);
  }

  final sep = Platform.pathSeparator;
  String pathOf(List<String> segments) => [dest.path, ...segments].join(sep);

  dest.createSync(recursive: true);
  final executables = <String>[];
  for (final e in entries) {
    if (links.containsKey(e.key)) continue;
    final path = pathOf(e.segments);
    if (e.file.isDirectory) {
      Directory(path).createSync(recursive: true);
      continue;
    }
    Directory(pathOf(e.segments.sublist(0, e.segments.length - 1)))
        .createSync(recursive: true);
    final out = OutputFileStream(path);
    try {
      e.file.writeContent(out);
    } finally {
      await out.close();
    }
    if (e.file.mode & 0x49 != 0) executables.add(path); // any x bit
  }
  // links last, so no file above went through one
  for (final e in entries) {
    final target = links[e.key];
    if (target == null) continue;
    final path = pathOf(e.segments);
    Directory(pathOf(e.segments.sublist(0, e.segments.length - 1)))
        .createSync(recursive: true);
    Link(path).createSync(target);
  }
  if (!Platform.isWindows && executables.isNotEmpty) {
    await (makeExecutable ?? _chmodExecutable)(executables);
  }
}

/// Reads a `.tar.gz` file: gunzips it next to itself first, so large
/// bundles never sit in memory whole. Call [TarGzArchive.close] after use.
class TarGzArchive {
  TarGzArchive._(this.archive, this._input, this._tar);

  final Archive archive;
  final InputFileStream _input;
  final File _tar;

  static Future<TarGzArchive> open(File tarGz) async {
    final tar = File('${tarGz.path}.tar');
    try {
      await tarGz.openRead().transform(gzip.decoder).pipe(tar.openWrite());
    } catch (e) {
      if (tar.existsSync()) tar.deleteSync();
      throw UnsafeArchiveException('not a gzip file: $e');
    }
    final input = InputFileStream(tar.path);
    try {
      final archive = TarDecoder().decodeStream(input);
      if (archive.isEmpty) throw const FormatException('empty');
      return TarGzArchive._(archive, input, tar);
    } catch (e) {
      await input.close();
      tar.deleteSync();
      throw UnsafeArchiveException('not a tar archive: $e');
    }
  }

  Future<void> close() async {
    await _input.close();
    if (_tar.existsSync()) _tar.deleteSync();
  }
}

/// Reads a `.zip` file from disk. Call [ZipArchive.close] after use.
class ZipArchive {
  ZipArchive._(this.archive, this._input);

  final Archive archive;
  final InputFileStream _input;

  static Future<ZipArchive> open(File zip) async {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      if (archive.isEmpty) throw const FormatException('empty');
      return ZipArchive._(archive, input);
    } catch (e) {
      await input.close();
      throw UnsafeArchiveException('not a zip archive: $e');
    }
  }

  Future<void> close() => _input.close();
}
