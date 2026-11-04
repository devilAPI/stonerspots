import 'dart:convert';
import 'dart:io';

import 'package:app/features/updater/installer.dart';
import 'package:app/features/updater/safe_extract.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

class _Quit implements Exception {}

Never _quit() => throw _Quit();

File writeTarGz(String path, Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.add(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
  }
  return File(path)
    ..writeAsBytesSync(GZipEncoder().encode(TarEncoder().encode(a)));
}

File writeZip(String path, Map<String, String> files) {
  final a = Archive();
  for (final e in files.entries) {
    a.add(ArchiveFile.bytes(e.key, utf8.encode(e.value)));
  }
  return File(path)..writeAsBytesSync(ZipEncoder().encode(a));
}

void main() {
  late Directory tmp;
  late Directory install;
  late List<String> relaunched;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('install');
    install = Directory('${tmp.path}/stonerspots')..createSync();
    File('${install.path}/app').writeAsStringSync('old');
    relaunched = [];
  });
  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+w', tmp.path]);
    tmp.deleteSync(recursive: true);
  });

  DirectorySwapInstaller linux() => DirectorySwapInstaller(
    installDir: install.path,
    mustContain: 'app',
    relaunch: (d) async => relaunched.add(d),
    quit: _quit,
    makeExecutable: (_) async {},
  );

  group('Linux', () {
    test('swaps the bundle, relaunches, cleans up next start', () async {
      final update = writeTarGz('${tmp.path}/u.tar.gz', {
        './app': 'new',
        './lib/libapp.so': 'so',
      });
      final i = linux();
      expect(await i.blocker(), isNull);
      await expectLater(i.install(update), throwsA(isA<_Quit>()));
      expect(File('${install.path}/app').readAsStringSync(), 'new');
      expect(File('${install.path}/lib/libapp.so').existsSync(), isTrue);
      expect(File('${i.oldPath}/app').readAsStringSync(), 'old');
      expect(Directory(i.stagingPath).existsSync(), isFalse);
      expect(relaunched, [install.path]);
      expect(update.existsSync(), isFalse); // unpacked, so gone

      await linux().cleanUp(); // next start
      expect(Directory(i.oldPath).existsSync(), isFalse);
      expect(File('${install.path}/app').readAsStringSync(), 'new');
    });

    test('an update without the executable leaves everything as is', () async {
      final update = writeTarGz('${tmp.path}/u.tar.gz', {'./other': 'x'});
      final i = linux();
      await expectLater(i.install(update), throwsA(isA<InstallException>()));
      expect(File('${install.path}/app').readAsStringSync(), 'old');
      expect(Directory(i.stagingPath).existsSync(), isFalse);
      expect(relaunched, isEmpty);
    });

    test('a hostile archive leaves everything as is', () async {
      final a = Archive()
        ..add(ArchiveFile.bytes('./app', utf8.encode('new')))
        ..add(ArchiveFile.bytes('../evil', utf8.encode('evil')));
      final update = File('${tmp.path}/u.tar.gz')
        ..writeAsBytesSync(GZipEncoder().encode(TarEncoder().encode(a)));
      final i = linux();
      await expectLater(
        i.install(update),
        throwsA(isA<UnsafeArchiveException>()),
      );
      expect(File('${tmp.path}/evil').existsSync(), isFalse);
      expect(File('${install.path}/app').readAsStringSync(), 'old');
      expect(Directory(i.stagingPath).existsSync(), isFalse);
    });

    test(
      'a folder the user can\'t write to blocks the in-app install',
      () async {
        Process.runSync('chmod', ['555', tmp.path]);
        expect(await linux().blocker(), InstallBlocker.notWritable);
      },
      skip: Platform.isWindows || _isRoot() ? 'needs POSIX, not root' : false,
    );
  }, skip: Platform.isWindows ? 'POSIX paths' : false);

  test('macOS: the .app inside the zip replaces the installed one', () async {
    final app = Directory('${tmp.path}/Stonerspots.app');
    Directory('${app.path}/Contents').createSync(recursive: true);
    File('${app.path}/Contents/Info.plist').writeAsStringSync('old');
    final update = writeZip('${tmp.path}/u.zip', {
      'Stonerspots.app/Contents/Info.plist': 'new',
      'Stonerspots.app/Contents/MacOS/Stonerspots': 'bin',
    });
    final i = DirectorySwapInstaller(
      installDir: app.path,
      appBundle: true,
      mustContain: 'Contents/Info.plist',
      relaunch: (d) async => relaunched.add(d),
      quit: _quit,
      makeExecutable: (_) async {},
    );
    await expectLater(i.install(update), throwsA(isA<_Quit>()));
    expect(File('${app.path}/Contents/Info.plist').readAsStringSync(), 'new');
    expect(Directory(i.stagingPath).existsSync(), isFalse);
    expect(relaunched, [app.path]);
  }, skip: Platform.isWindows ? 'POSIX paths' : false);

  group('Windows helper', () {
    test('quotes paths for PowerShell', () {
      expect(
        psQuote(r"C:\Users\O'Brien\Stonerspots"),
        r"'C:\Users\O''Brien\Stonerspots'",
      );
      final s = windowsSwapScript(
        waitPid: 42,
        installDir: r"C:\Apps\Stoner's",
        stagedDir: r"C:\Apps\.Stoner's.update",
        oldDir: r"C:\Apps\.Stoner's.old",
        exe: r"C:\Apps\Stoner's\app.exe",
      );
      expect(s, contains(r"$install = 'C:\Apps\Stoner''s'"));
      expect(s, contains('Wait-Process -Id 42'));
      // the old folder goes back if the new one can't be moved in
      expect(
        s,
        contains(
          r'catch { Rename-Item -LiteralPath $old -NewName (Split-Path $install -Leaf) }',
        ),
      );
    });

    test('-EncodedCommand is base64 of UTF-16LE', () {
      const script = 'Write-Output "Grüße"';
      final bytes = base64.decode(WindowsInstaller.encodeCommand(script));
      final units = [
        for (var i = 0; i < bytes.length; i += 2) bytes[i] | bytes[i + 1] << 8,
      ];
      expect(String.fromCharCodes(units), script);
    });
  });
}

bool _isRoot() {
  try {
    return Process.runSync('id', ['-u']).stdout.toString().trim() == '0';
  } catch (_) {
    return false;
  }
}
