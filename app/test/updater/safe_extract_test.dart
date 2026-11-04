import 'dart:convert';
import 'dart:io';

import 'package:app/features/updater/safe_extract.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveFile file(String name, String text, {int mode = 0x1a4}) =>
    ArchiveFile.bytes(name, utf8.encode(text))..mode = mode;

ArchiveFile link(String name, String target) =>
    ArchiveFile.symlink(name, target);

Archive archiveOf(List<ArchiveFile> files) {
  final a = Archive();
  files.forEach(a.add);
  return a;
}

void main() {
  late Directory tmp;
  late Directory dest;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('extract');
    dest = Directory('${tmp.path}/out');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final unsafe = throwsA(isA<UnsafeArchiveException>());

  Future<void> extract(List<ArchiveFile> files, {bool links = false}) =>
      extractArchiveSafely(
        archiveOf(files),
        dest,
        allowSymlinks: links,
        makeExecutable: (_) async {},
      );

  test('unpacks a normal bundle', () async {
    await extract([
      ArchiveFile.directory('./'),
      file('./app', 'binary', mode: 0x1ed),
      file('./lib/libapp.so', 'lib'),
      ArchiveFile.directory('./data/'),
      file('data/flutter_assets/version.json', '{}'),
    ]);
    expect(File('${dest.path}/app').readAsStringSync(), 'binary');
    expect(File('${dest.path}/lib/libapp.so').existsSync(), isTrue);
    expect(
      File('${dest.path}/data/flutter_assets/version.json').existsSync(),
      isTrue,
    );
  });

  test('path traversal is refused before anything is written', () async {
    for (final name in [
      '../evil',
      'a/../../evil',
      './../evil',
      '/etc/evil',
      '..\\evil',
      'a\\..\\..\\evil',
      'C:\\evil',
      'C:evil',
      'a/file.txt:stream',
    ]) {
      await expectLater(
        extract([file('ok', 'ok'), file(name, 'evil')]),
        unsafe,
        reason: name,
      );
      expect(dest.existsSync(), isFalse, reason: name);
      expect(File('${tmp.path}/evil').existsSync(), isFalse);
    }
  });

  test('a name inside the folder may contain dots', () async {
    await extract([file('a/..b/c..d', 'ok'), file('./x/./y', 'ok')]);
    expect(File('${dest.path}/a/..b/c..d').existsSync(), isTrue);
    expect(File('${dest.path}/x/y').existsSync(), isTrue);
  });

  test('symbolic links are refused unless allowed', () async {
    await expectLater(extract([link('l', 'app'), file('app', 'x')]), unsafe);
    expect(dest.existsSync(), isFalse);
  });

  test('hard links are always refused', () async {
    final hard = link('h', '/etc/passwd')..isHardLink = true;
    await expectLater(extract([hard], links: true), unsafe);
  });

  test('links inside the bundle are kept (macOS frameworks)', () async {
    await extract([
      file('X.app/Contents/Frameworks/F.framework/Versions/A/F', 'lib'),
      link('X.app/Contents/Frameworks/F.framework/Versions/Current', 'A'),
      link('X.app/Contents/Frameworks/F.framework/F', 'Versions/Current/F'),
    ], links: true);
    final f = '${dest.path}/X.app/Contents/Frameworks/F.framework/F';
    expect(FileSystemEntity.isLinkSync(f), isTrue);
    expect(File(f).readAsStringSync(), 'lib');
  });

  test('links that point outside are refused', () async {
    for (final bad in [
      [link('l', '..')],
      [link('l', '/etc')],
      [link('a/l', '../../x')],
      // through another link: d/up is the folder itself, so d/up/.. leaves
      [file('d/f', 'x'), link('d/up', '..'), link('d/m', 'up/..')],
      [link('a', 'b'), link('b', 'a')], // loop
    ]) {
      await expectLater(extract(bad, links: true), unsafe);
      expect(dest.existsSync(), isFalse);
    }
  });

  test('nothing is written below a link', () async {
    await expectLater(
      extract([link('d', '.'), file('d/x', 'x')], links: true),
      unsafe,
    );
  });

  test('a name twice is refused', () async {
    await expectLater(extract([file('a', '1'), file('./a', '2')]), unsafe);
  });

  test('size and entry caps', () async {
    await expectLater(
      extractArchiveSafely(
        archiveOf([file('a', 'x' * 100)]),
        dest,
        maxTotalBytes: 50,
      ),
      unsafe,
    );
    await expectLater(
      extractArchiveSafely(
        archiveOf([file('a', '1'), file('b', '2')]),
        dest,
        maxEntries: 1,
      ),
      unsafe,
    );
  });

  test('refuses to unpack over an existing folder', () async {
    dest.createSync();
    await expectLater(extract([file('a', '1')]), unsafe);
  });

  test('a real tar.gz from tar(1), with the executable bit', () async {
    final src = Directory('${tmp.path}/bundle')..createSync();
    File('${src.path}/app').writeAsStringSync('#!/bin/sh\n');
    Directory('${src.path}/lib').createSync();
    File('${src.path}/lib/libapp.so').writeAsStringSync('so');
    await Process.run('chmod', ['755', '${src.path}/app']);
    final tgz = File('${tmp.path}/b.tar.gz');
    final r = await Process.run('tar', ['-czf', tgz.path, '-C', src.path, '.']);
    expect(r.exitCode, 0, reason: '${r.stderr}');

    final a = await TarGzArchive.open(tgz);
    try {
      await extractArchiveSafely(a.archive, dest);
    } finally {
      await a.close();
    }
    expect(File('${dest.path}/lib/libapp.so').readAsStringSync(), 'so');
    final mode = File('${dest.path}/app').statSync().mode;
    expect(mode & 0x40, isNot(0)); // u+x
    expect(File('${tgz.path}.tar').existsSync(), isFalse);
  }, skip: Platform.isLinux || Platform.isMacOS ? false : 'needs tar(1)');

  test('junk is not an archive', () async {
    final f = File('${tmp.path}/junk.tar.gz')..writeAsStringSync('junk');
    await expectLater(TarGzArchive.open(f), unsafe);
    final z = File('${tmp.path}/junk.zip')..writeAsStringSync('junk');
    await expectLater(ZipArchive.open(z), unsafe);
  });

  test('a zip round trip', () async {
    final zip = File('${tmp.path}/a.zip')
      ..writeAsBytesSync(
        ZipEncoder().encode(archiveOf([file('app.exe', 'exe')])),
      );
    final a = await ZipArchive.open(zip);
    try {
      await extractArchiveSafely(a.archive, dest);
    } finally {
      await a.close();
    }
    expect(File('${dest.path}/app.exe').readAsStringSync(), 'exe');
  });

  test('entry names', () {
    expect(safeEntrySegments('./a/b/'), ['a', 'b']);
    expect(safeEntrySegments('a\\b'), ['a', 'b']);
    expect(() => safeEntrySegments('a\u0000b'), unsafe);
  });
}
