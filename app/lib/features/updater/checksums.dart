import 'dart:io';

import 'package:crypto/crypto.dart';

/// The `sha256sum` output of a release: file name -> lowercase hex digest.
/// Throws [FormatException] for anything that is not a clean `sha256sum`
/// line, or a name listed twice: a signed file has no excuse for either.
Map<String, String> parseSha256Sums(String text) {
  final out = <String, String>{};
  final line = RegExp(r'^([0-9a-fA-F]{64}) [ *](.+)$');
  for (final raw in text.split('\n')) {
    final l = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
    if (l.trim().isEmpty) continue;
    final m = line.firstMatch(l);
    if (m == null) throw FormatException('not a sha256sum line: $l');
    final name = m.group(2)!;
    if (out.containsKey(name)) throw FormatException('$name listed twice');
    out[name] = m.group(1)!.toLowerCase();
  }
  return out;
}

/// SHA-256 of [file] as lowercase hex, read in chunks.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Whether [file]'s SHA-256 is [expectedHex] (case-insensitive).
Future<bool> fileMatchesSha256(File file, String expectedHex) async =>
    await sha256OfFile(file) == expectedHex.toLowerCase();
