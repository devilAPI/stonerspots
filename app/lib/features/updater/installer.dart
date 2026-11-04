import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';

import 'safe_extract.dart';

/// Why an update can't be installed from inside the app.
enum InstallBlocker {
  /// The app's folder (or the one it is in) is not writable for this user.
  notWritable,

  /// Android: "install unknown apps" is off for Stonerspots.
  needsInstallPermission,
}

class InstallException implements Exception {
  const InstallException(this.message);

  final String message;

  @override
  String toString() => 'InstallException: $message';
}

/// Installs a downloaded and already verified update file.
abstract class UpdateInstaller {
  /// Null when [install] can work here, else why not.
  Future<InstallBlocker?> blocker();

  /// Installs [verified]. On desktop this relaunches and quits the app; on
  /// Android it hands the file to the system installer.
  Future<void> install(File verified);

  /// Removes what a previous update left behind. Called once at start.
  Future<void> cleanUp() async {}

  /// Android: opens the "install unknown apps" setting for this app.
  Future<void> openPermissionSettings() async {}
}

/// Android: the system package installer, through a small platform channel
/// in MainActivity (FileProvider + ACTION_VIEW). The APK must be signed
/// with the installed app's key, or Android refuses it.
class AndroidInstaller extends UpdateInstaller {
  AndroidInstaller({MethodChannel? channel, this.updatesDir})
    : _channel = channel ?? const MethodChannel('de.stonerspots.app/updater');

  final MethodChannel _channel;

  /// Where downloads wait for the installer (cache/updates).
  final Future<Directory> Function()? updatesDir;

  /// The APK of the last update is no longer needed once the app runs again.
  @override
  Future<void> cleanUp() async {
    final dir = await updatesDir?.call();
    if (dir != null) _deleteDirIfThere(dir.path);
  }

  @override
  Future<InstallBlocker?> blocker() async {
    try {
      final ok = await _channel.invokeMethod<bool>('canInstall');
      return ok == true ? null : InstallBlocker.needsInstallPermission;
    } on PlatformException {
      return InstallBlocker.needsInstallPermission;
    } on MissingPluginException {
      return InstallBlocker.needsInstallPermission;
    }
  }

  @override
  Future<void> openPermissionSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  @override
  Future<void> install(File verified) async {
    try {
      await _channel.invokeMethod<void>('install', verified.path);
    } on PlatformException catch (e) {
      throw InstallException(e.message ?? e.code);
    }
  }
}

/// Whether [dir] lets this user create and remove entries.
bool directoryWritable(Directory dir) {
  final probe = Directory(
    '${dir.path}${Platform.pathSeparator}.stonerspots-write-test-$pid',
  );
  try {
    probe.createSync();
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

/// Deletes [path] if it is a real directory (never through a link).
void _deleteDirIfThere(String path) {
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else if (type == FileSystemEntityType.link) {
      Link(path).deleteSync();
    }
  } catch (_) {}
}

String _parentOf(String path) => File(path).parent.path;

String _leafOf(String path) => path.split(Platform.pathSeparator).last;

/// Opens the downloaded archive; Linux bundles are .tar.gz, the others .zip.
Future<(Archive, Future<void> Function())> _openArchive(File file) async {
  if (file.path.endsWith('.tar.gz')) {
    final a = await TarGzArchive.open(file);
    return (a.archive, a.close);
  }
  final a = await ZipArchive.open(file);
  return (a.archive, a.close);
}

/// Linux and macOS: unpack next to the installed folder, swap the folders
/// (the running app keeps its open files), start the new one and quit.
///
/// Linux: [installDir] is the bundle folder holding the executable.
/// macOS: [installDir] is the `.app`; the zip holds one `*.app` folder.
class DirectorySwapInstaller extends UpdateInstaller {
  DirectorySwapInstaller({
    required this.installDir,
    required this.relaunch,
    required this.mustContain,
    this.appBundle = false,
    this.quit = _quit,
    this.makeExecutable,
  });

  /// From the running executable.
  factory DirectorySwapInstaller.forCurrentApp() {
    final exe = Platform.resolvedExecutable;
    if (Platform.isMacOS) {
      // X.app/Contents/MacOS/<exe>
      final app = File(exe).parent.parent.parent.path;
      return DirectorySwapInstaller(
        installDir: app,
        appBundle: true,
        mustContain: 'Contents/Info.plist',
        relaunch: (dir) => Process.start('/usr/bin/open', [
          '-n',
          dir,
        ], mode: ProcessStartMode.detached),
      );
    }
    final dir = _parentOf(exe);
    final name = _leafOf(exe);
    return DirectorySwapInstaller(
      installDir: dir,
      mustContain: name,
      relaunch: (d) => Process.start(
        '$d${Platform.pathSeparator}$name',
        const [],
        workingDirectory: d,
        mode: ProcessStartMode.detached,
      ),
    );
  }

  final String installDir;
  final bool appBundle;

  /// A file the new folder must have (relative, `/`-separated).
  final String mustContain;
  final Future<Object?> Function(String installDir) relaunch;
  final Never Function() quit;
  final MakeExecutable? makeExecutable;

  static Never _quit() => exit(0);

  String get _parent => _parentOf(installDir);
  String get _leaf => _leafOf(installDir);
  String get stagingPath => '$_parent${Platform.pathSeparator}.$_leaf.update';
  String get oldPath => '$_parent${Platform.pathSeparator}.$_leaf.old';

  @override
  Future<InstallBlocker?> blocker() async =>
      directoryWritable(Directory(_parent)) &&
          directoryWritable(Directory(installDir))
      ? null
      : InstallBlocker.notWritable;

  @override
  Future<void> cleanUp() async {
    _deleteDirIfThere(oldPath);
    _deleteDirIfThere(stagingPath);
  }

  @override
  Future<void> install(File verified) async {
    await cleanUp();
    final (archive, close) = await _openArchive(verified);
    try {
      await extractArchiveSafely(
        archive,
        Directory(stagingPath),
        allowSymlinks: appBundle, // frameworks in a .app are full of links
        makeExecutable: makeExecutable,
      );
    } on Object {
      _deleteDirIfThere(stagingPath);
      rethrow;
    } finally {
      await close();
      _deleteFileQuietly(verified); // unpacked, no longer needed
    }
    var newDir = stagingPath;
    if (appBundle) {
      final apps = Directory(stagingPath)
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => d.path.endsWith('.app'))
          .toList();
      if (apps.length != 1) {
        _deleteDirIfThere(stagingPath);
        throw const InstallException('the zip must hold exactly one .app');
      }
      newDir = apps.single.path;
    }
    final check = '$newDir/$mustContain'.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    if (!File(check).existsSync()) {
      _deleteDirIfThere(stagingPath);
      throw InstallException('$mustContain missing from the update');
    }

    try {
      Directory(installDir).renameSync(oldPath);
    } catch (e) {
      _deleteDirIfThere(stagingPath);
      throw InstallException('could not move the app aside: $e');
    }
    try {
      Directory(newDir).renameSync(installDir);
    } catch (e) {
      Directory(oldPath).renameSync(installDir); // put the old one back
      _deleteDirIfThere(stagingPath);
      throw InstallException('could not move the update in place: $e');
    }
    if (appBundle) _deleteDirIfThere(stagingPath);
    try {
      await relaunch(installDir);
    } catch (_) {
      // The new version is in place; the user starts it by hand.
    }
    quit();
  }
}

/// Quotes [s] for a single-quoted PowerShell string.
String psQuote(String s) => "'${s.replaceAll("'", "''")}'";

/// The PowerShell script that waits for [waitPid] to exit, swaps
/// [installDir] for [stagedDir] (keeping the old one as [oldDir] until the
/// swap worked, and putting it back if it didn't) and starts [exe].
String windowsSwapScript({
  required int waitPid,
  required String installDir,
  required String stagedDir,
  required String oldDir,
  required String exe,
}) =>
    '''
\$ErrorActionPreference = 'Stop'
\$install = ${psQuote(installDir)}
\$staged = ${psQuote(stagedDir)}
\$old = ${psQuote(oldDir)}
\$exe = ${psQuote(exe)}
try { Wait-Process -Id $waitPid -Timeout 60 } catch {}
Start-Sleep -Milliseconds 500
\$moved = \$false
for (\$i = 0; \$i -lt 20 -and -not \$moved; \$i++) {
  try { Rename-Item -LiteralPath \$install -NewName (Split-Path \$old -Leaf); \$moved = \$true }
  catch { Start-Sleep -Milliseconds 500 }
}
\$ok = \$false
if (\$moved) {
  try { Rename-Item -LiteralPath \$staged -NewName (Split-Path \$install -Leaf); \$ok = \$true }
  catch { Rename-Item -LiteralPath \$old -NewName (Split-Path \$install -Leaf) }
}
Start-Process -FilePath \$exe -WorkingDirectory \$install
if (\$ok) { Remove-Item -LiteralPath \$old -Recurse -Force -ErrorAction SilentlyContinue }
else { Remove-Item -LiteralPath \$staged -Recurse -Force -ErrorAction SilentlyContinue }
''';

/// Windows: a running .exe can't be moved, so the swap happens in a hidden
/// PowerShell process after the app has quit. The script goes in as
/// `-EncodedCommand` (no script file, so no execution policy prompt, and
/// any characters in the path survive).
class WindowsInstaller extends UpdateInstaller {
  WindowsInstaller({
    required this.installDir,
    required this.exeName,
    this.quit = _quit,
    this.startHelper = _startHelper,
  });

  factory WindowsInstaller.forCurrentApp() {
    final exe = Platform.resolvedExecutable;
    return WindowsInstaller(installDir: _parentOf(exe), exeName: _leafOf(exe));
  }

  final String installDir;
  final String exeName;
  final Never Function() quit;
  final Future<Object?> Function(String encodedScript) startHelper;

  static Never _quit() => exit(0);

  static Future<Object?> _startHelper(String encoded) =>
      Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        encoded,
      ], mode: ProcessStartMode.detached);

  String get _parent => _parentOf(installDir);
  String get _leaf => _leafOf(installDir);
  String get stagingPath => '$_parent\\.$_leaf.update';
  String get oldPath => '$_parent\\.$_leaf.old';

  @override
  Future<InstallBlocker?> blocker() async =>
      directoryWritable(Directory(_parent)) &&
          directoryWritable(Directory(installDir))
      ? null
      : InstallBlocker.notWritable;

  @override
  Future<void> cleanUp() async {
    _deleteDirIfThere(oldPath);
    _deleteDirIfThere(stagingPath);
  }

  /// PowerShell's `-EncodedCommand`: base64 of UTF-16LE.
  static String encodeCommand(String script) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[2 * i] = units[i] & 0xff;
      bytes[2 * i + 1] = units[i] >> 8;
    }
    return base64.encode(bytes);
  }

  @override
  Future<void> install(File verified) async {
    await cleanUp();
    final (archive, close) = await _openArchive(verified);
    try {
      await extractArchiveSafely(archive, Directory(stagingPath));
    } on Object {
      _deleteDirIfThere(stagingPath);
      rethrow;
    } finally {
      await close();
      _deleteFileQuietly(verified); // unpacked, no longer needed
    }
    if (!File('$stagingPath\\$exeName').existsSync()) {
      _deleteDirIfThere(stagingPath);
      throw InstallException('$exeName missing from the update');
    }
    final script = windowsSwapScript(
      waitPid: pid,
      installDir: installDir,
      stagedDir: stagingPath,
      oldDir: oldPath,
      exe: '$installDir\\$exeName',
    );
    try {
      await startHelper(encodeCommand(script));
    } catch (e) {
      _deleteDirIfThere(stagingPath);
      throw InstallException('could not start the update helper: $e');
    }
    quit();
  }
}

void _deleteFileQuietly(File f) {
  try {
    f.deleteSync();
  } catch (_) {}
}
