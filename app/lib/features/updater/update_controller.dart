import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import 'checksums.dart';
import 'downloader.dart';
import 'installer.dart';
import 'release.dart';
import 'release_source.dart';
import 'safe_extract.dart';
import 'sshsig.dart';

/// Namespace the release checksums are signed in (`ssh-keygen -Y sign -n`).
const releaseSignatureNamespace = 'stonerspots-release';

/// Largest app file the updater downloads.
const maxUpdateBytes = 512 * 1024 * 1024;

/// How this build updates itself, fixed at build time:
/// `--dart-define=UPDATE_CHANNEL=dev|release` and
/// `--dart-define=RELEASE_SIGNING_PUBKEY=ssh-ed25519 AAAA...`.
class UpdaterConfig {
  const UpdaterConfig({
    required this.channel,
    required this.platform,
    required this.signingKey,
  });

  factory UpdaterConfig.fromEnvironment() => UpdaterConfig(
    channel: UpdateChannel.parse(
      const String.fromEnvironment('UPDATE_CHANNEL'),
    ),
    platform: currentUpdatePlatform(),
    signingKey: SshEd25519PublicKey.tryParse(
      const String.fromEnvironment('RELEASE_SIGNING_PUBKEY'),
    ),
  );

  /// Null for a build without a channel (local builds): no update checks.
  final UpdateChannel? channel;

  /// Null where the app can't update itself (web, iOS).
  final UpdatePlatform? platform;

  /// Null when no key was compiled in: updates then only open the release
  /// page, nothing is installed.
  final SshEd25519PublicKey? signingKey;

  bool get enabled => channel != null && platform != null;
}

UpdatePlatform? currentUpdatePlatform() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => UpdatePlatform.android,
    TargetPlatform.linux => UpdatePlatform.linux,
    TargetPlatform.windows => UpdatePlatform.windows,
    TargetPlatform.macOS => UpdatePlatform.macos,
    _ => null,
  };
}

/// The release page on GitHub, built from the tag (never a URL from the
/// API answer).
Uri releasePageUrl(String tag) => Uri.https(
  'github.com',
  '/devilAPI/stonerspots/releases/tag/${Uri.encodeComponent(tag)}',
);

enum UpdateStage {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  installing,

  /// Android: the system installer has the APK now.
  handedOff,
  failed,
}

enum UpdateProblem {
  /// No signing key in this build: nothing is installed from inside the app.
  noSigningKey,

  /// The app's folder is not writable: update by hand.
  notWritable,

  /// Android: "install unknown apps" is off for Stonerspots.
  needsInstallPermission,
  rateLimited,
  offline,

  /// The release lacks this platform's file or the signed checksums.
  assetMissing,

  /// The checksums' signature is missing, wrong or doesn't cover the file.
  signatureInvalid,
  checksumMismatch,
  downloadFailed,
  installFailed,
}

@immutable
class UpdateState {
  const UpdateState({
    this.stage = UpdateStage.idle,
    this.release,
    this.installed,
    this.progress,
    this.problem,
    this.installBlocked,
    this.dismissed = false,
  });

  final UpdateStage stage;

  /// The newer release, once one was found.
  final ReleaseInfo? release;
  final InstalledVersion? installed;

  /// 0..1 while downloading; null when the size is unknown.
  final double? progress;

  /// What went wrong last.
  final UpdateProblem? problem;

  /// Why "Update now" opens the release page instead of installing.
  final UpdateProblem? installBlocked;

  /// "Later": no banner for the rest of this session.
  final bool dismissed;

  bool get busy =>
      stage == UpdateStage.checking ||
      stage == UpdateStage.downloading ||
      stage == UpdateStage.verifying ||
      stage == UpdateStage.installing;

  bool get showBanner => release != null && !dismissed;

  UpdateState copyWith({
    UpdateStage? stage,
    ReleaseInfo? release,
    InstalledVersion? installed,
    double? progress,
    UpdateProblem? problem,
    UpdateProblem? installBlocked,
    bool? dismissed,
    bool clearRelease = false,
    bool clearProblem = false,
    bool clearBlocked = false,
  }) => UpdateState(
    stage: stage ?? this.stage,
    release: clearRelease ? null : release ?? this.release,
    installed: installed ?? this.installed,
    progress: progress,
    problem: clearProblem ? null : problem ?? this.problem,
    installBlocked: clearBlocked ? null : installBlocked ?? this.installBlocked,
    dismissed: dismissed ?? this.dismissed,
  );
}

final updaterConfigProvider = Provider<UpdaterConfig>(
  (ref) => UpdaterConfig.fromEnvironment(),
);

final installedVersionLoaderProvider =
    Provider<Future<InstalledVersion> Function()>(
      (ref) => () async {
        final info = await PackageInfo.fromPlatform();
        return InstalledVersion(
          version: info.version,
          buildNumber: info.buildNumber,
        );
      },
    );

/// A plain client: no API auth headers ever go to GitHub.
final updaterDioProvider = Provider<Dio>((ref) => Dio());

/// The channel the updater follows: the user's pick in the settings, else
/// the one this build was made for. Null for a local build (no updates).
final updateChannelProvider =
    NotifierProvider<UpdateChannelSetting, UpdateChannel?>(
      UpdateChannelSetting.new,
    );

class UpdateChannelSetting extends Notifier<UpdateChannel?> {
  static const storeKey = 'update_channel';

  @override
  UpdateChannel? build() {
    final built = ref.watch(updaterConfigProvider).channel;
    if (built == null) return null;
    final picked = ref.watch(settingsStoreProvider).getString(storeKey);
    return UpdateChannel.parse(picked ?? '') ?? built;
  }

  void set(UpdateChannel channel) {
    if (state == null || channel == state) return;
    state = channel;
    ref.read(settingsStoreProvider).setString(storeKey, channel.name);
  }
}

final releaseSourceProvider = Provider<ReleaseSource>(
  (ref) => ReleaseSource(
    dio: ref.watch(updaterDioProvider),
    store: ref.watch(settingsStoreProvider),
    url: releasesApiUrlFor(
      ref.watch(updateChannelProvider) ?? UpdateChannel.dev,
    ),
  ),
);

final safeDownloaderProvider = Provider<SafeDownloader>(
  (ref) => SafeDownloader(ref.watch(updaterDioProvider)),
);

final updateInstallerProvider = Provider<UpdateInstaller?>((ref) {
  return switch (ref.watch(updaterConfigProvider).platform) {
    UpdatePlatform.android => AndroidInstaller(
      updatesDir: () async =>
          Directory('${(await getTemporaryDirectory()).path}/updates'),
    ),
    UpdatePlatform.windows => WindowsInstaller.forCurrentApp(),
    UpdatePlatform.linux ||
    UpdatePlatform.macos => DirectorySwapInstaller.forCurrentApp(),
    null => null,
  };
});

/// A folder for one download. Android: the cache folder the FileProvider
/// shares (emptied first). Desktop: a fresh private temp folder.
final updateWorkDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    if (!kIsWeb && Platform.isAndroid) {
      final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return dir.create(recursive: true);
    }
    return Directory.systemTemp.createTemp('stonerspots-update-');
  },
);

final openExternalUrlProvider = Provider<Future<void> Function(Uri)>(
  (ref) => (uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  },
);

/// "Check for updates automatically", on by default.
final autoUpdateCheckProvider = NotifierProvider<BoolSetting, bool>(
  () => BoolSetting('auto_update_check', defaultValue: true),
);

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  static const _skippedKey = 'updater.skipped_tag';

  CancelToken? _cancel;
  bool _started = false;

  @override
  UpdateState build() => const UpdateState();

  UpdaterConfig get _config => ref.read(updaterConfigProvider);

  bool get supported => _config.enabled;

  /// Once per app start: clears what an earlier update left behind, then
  /// checks if automatic checks are on.
  Future<void> onAppStart() async {
    if (_started || !supported) return;
    _started = true;
    try {
      await ref.read(updateInstallerProvider)?.cleanUp();
    } catch (_) {}
    if (!ref.read(autoUpdateCheckProvider)) return;
    await _check(manual: false);
  }

  /// "Check for updates" in the settings: asks GitHub even within the 6 h,
  /// and shows a skipped version again.
  Future<void> checkNow() => _check(manual: true);

  Future<void> _check({required bool manual}) async {
    if (!supported || state.busy) return;
    state = state.copyWith(stage: UpdateStage.checking, clearProblem: true);
    final channel = ref.read(updateChannelProvider)!;
    InstalledVersion installed;
    try {
      installed = await ref.read(installedVersionLoaderProvider)();
    } catch (_) {
      state = state.copyWith(stage: UpdateStage.idle);
      return;
    }
    final result = await ref
        .read(releaseSourceProvider)
        .releases(force: manual);
    final releases = result.releases;
    if (releases == null) {
      state = state.copyWith(
        stage: manual ? UpdateStage.failed : UpdateStage.idle,
        installed: installed,
        problem: result.rateLimited
            ? UpdateProblem.rateLimited
            : UpdateProblem.offline,
      );
      return;
    }
    final store = ref.read(settingsStoreProvider);
    final pick = pickUpdate(
      releases: releases,
      channel: channel,
      installed: installed,
      skippedTag: manual ? null : store.getString(_skippedKey),
      switching: channel != _config.channel,
    );
    if (pick == null) {
      state = UpdateState(
        stage: UpdateStage.upToDate,
        installed: installed,
        problem: result.rateLimited ? UpdateProblem.rateLimited : null,
      );
      return;
    }
    if (manual) await store.setString(_skippedKey, null);
    state = UpdateState(
      stage: UpdateStage.available,
      release: pick,
      installed: installed,
      installBlocked: await _installBlocker(),
    );
  }

  /// Why the update can't be installed in the app right now, if at all.
  Future<UpdateProblem?> _installBlocker() async {
    if (_config.signingKey == null) return UpdateProblem.noSigningKey;
    final installer = ref.read(updateInstallerProvider);
    if (installer == null) return UpdateProblem.notWritable;
    try {
      return switch (await installer.blocker()) {
        null => null,
        InstallBlocker.notWritable => UpdateProblem.notWritable,
        InstallBlocker.needsInstallPermission =>
          UpdateProblem.needsInstallPermission,
      };
    } catch (_) {
      return UpdateProblem.notWritable;
    }
  }

  void later() => state = state.copyWith(dismissed: true);

  Future<void> skip() async {
    final tag = state.release?.tag;
    if (tag != null) {
      await ref.read(settingsStoreProvider).setString(_skippedKey, tag);
    }
    _cancel?.cancel();
    state = UpdateState(stage: UpdateStage.idle, installed: state.installed);
  }

  Future<void> openReleasePage() async {
    final tag = state.release?.tag;
    if (tag == null) return;
    try {
      await ref.read(openExternalUrlProvider)(releasePageUrl(tag));
    } catch (_) {}
  }

  Future<void> openInstallPermissionSettings() async {
    await ref.read(updateInstallerProvider)?.openPermissionSettings();
  }

  void cancel() => _cancel?.cancel();

  void _fail(UpdateProblem problem) =>
      state = state.copyWith(stage: UpdateStage.failed, problem: problem);

  /// "Update now": download, verify, install. Anything that can't be
  /// verified is never installed; without a key or a writable folder the
  /// release page opens instead.
  Future<void> updateNow() async {
    final release = state.release;
    final platform = _config.platform;
    if (release == null || platform == null || state.busy) return;
    final key = _config.signingKey;
    final blocker = await _installBlocker();
    state = blocker == null
        ? state.copyWith(clearBlocked: true)
        : state.copyWith(installBlocked: blocker);
    if (key == null ||
        blocker == UpdateProblem.noSigningKey ||
        blocker == UpdateProblem.notWritable) {
      await openReleasePage();
      return;
    }
    if (blocker == UpdateProblem.needsInstallPermission) {
      return _fail(UpdateProblem.needsInstallPermission);
    }

    final sumsAsset = release.asset(appChecksumsName);
    final sigAsset = release.asset(appChecksumsSignatureName);
    final appAsset = release.appAsset(platform);
    // the name becomes a file name: nothing but a plain one
    if (sumsAsset == null ||
        appAsset == null ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(appAsset.name)) {
      return _fail(UpdateProblem.assetMissing);
    }
    if (sigAsset == null) return _fail(UpdateProblem.signatureInvalid);

    final cancel = _cancel = CancelToken();
    final downloader = ref.read(safeDownloaderProvider);
    Directory? work;
    try {
      state = state.copyWith(stage: UpdateStage.verifying, clearProblem: true);
      final sums = await downloader.fetchBytes(sumsAsset.url, cancel: cancel);
      final sig = await downloader.fetchBytes(
        sigAsset.url,
        maxBytes: 64 * 1024,
        cancel: cancel,
      );
      final String expected;
      try {
        await verifySshSignature(
          message: sums,
          armored: utf8.decode(sig),
          key: key,
          namespace: releaseSignatureNamespace,
        );
        final hash = parseSha256Sums(utf8.decode(sums))[appAsset.name];
        if (hash == null) throw const FormatException('file not listed');
        expected = hash;
      } on SshSignatureException {
        return _fail(UpdateProblem.signatureInvalid);
      } on FormatException {
        return _fail(UpdateProblem.signatureInvalid);
      }

      work = await ref.read(updateWorkDirProvider)();
      final file = File(
        '${work.path}${Platform.pathSeparator}${appAsset.name}',
      );
      state = state.copyWith(stage: UpdateStage.downloading, progress: 0);
      await downloader.download(
        appAsset.url,
        file,
        maxBytes: maxUpdateBytes,
        cancel: cancel,
        onProgress: (received, total) {
          final size = total ?? appAsset.size;
          state = state.copyWith(
            stage: UpdateStage.downloading,
            progress: size > 0 ? (received / size).clamp(0.0, 1.0) : null,
          );
        },
      );
      state = state.copyWith(stage: UpdateStage.verifying);
      if (!await fileMatchesSha256(file, expected)) {
        file.deleteSync();
        return _fail(UpdateProblem.checksumMismatch);
      }
      state = state.copyWith(stage: UpdateStage.installing);
      // Desktop: relaunches and quits, so nothing after this runs there.
      await ref.read(updateInstallerProvider)!.install(file);
      state = state.copyWith(stage: UpdateStage.handedOff);
    } on DownloadException catch (e) {
      if (e.cancelled) {
        state = state.copyWith(
          stage: UpdateStage.available,
          clearProblem: true,
        );
      } else {
        _fail(UpdateProblem.downloadFailed);
      }
    } on UnsafeArchiveException {
      _fail(UpdateProblem.installFailed);
    } on InstallException {
      _fail(UpdateProblem.installFailed);
    } on FileSystemException {
      _fail(UpdateProblem.installFailed);
    } finally {
      _cancel = null;
      // the APK must stay until the system installer has read it
      if (work != null && platform != UpdatePlatform.android) {
        try {
          work.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }
}
