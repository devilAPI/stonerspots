import 'dart:io';

import 'package:app/features/updater/checksums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('reads sha256sum output', () {
    final sums = parseSha256Sums(fixtureText('SHA256SUMS-apps.txt'));
    expect(sums.keys, [
      'stonerspots-dev-7-android.apk',
      'stonerspots-dev-7-linux-x64.tar.gz',
    ]);
    expect(
      sums['stonerspots-dev-7-linux-x64.tar.gz'],
      '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    );
  });

  test('binary marker, CRLF and upper case', () {
    final sums = parseSha256Sums(
      '${'AB' * 32} *a.zip\r\n${'cd' * 32}  b c.zip\n\n',
    );
    expect(sums, {'a.zip': 'ab' * 32, 'b c.zip': 'cd' * 32});
  });

  test('refuses anything else', () {
    for (final bad in [
      'abc  a.zip',
      '${'g' * 64}  a.zip',
      '${'a' * 64}a.zip',
      '${'a' * 64}  ',
      '# comment',
      '${'a' * 64}  a.zip\n${'b' * 64}  a.zip', // twice
    ]) {
      expect(() => parseSha256Sums(bad), throwsFormatException, reason: bad);
    }
  });

  test('SHA-256 of a file', () async {
    final dir = Directory.systemTemp.createTempSync('sums');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/test')..writeAsStringSync('test');
    const hash =
        '9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08';
    expect(await sha256OfFile(f), hash);
    expect(await fileMatchesSha256(f, hash.toUpperCase()), isTrue);
    expect(await fileMatchesSha256(f, 'a' * 64), isFalse);
    f.writeAsStringSync('tesT');
    expect(await fileMatchesSha256(f, hash), isFalse);
  });
}
