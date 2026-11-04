import 'dart:convert';
import 'dart:io';

import 'package:app/core/settings.dart';
import 'package:app/features/updater/installer.dart';
import 'package:app/features/updater/release.dart';
import 'package:app/features/updater/release_source.dart';
import 'package:app/features/updater/sshsig.dart';
import 'package:app/features/updater/update_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fakes.dart';

class FakeInstaller extends UpdateInstaller {
  InstallBlocker? block;
  final installed = <String>[];
  int cleanUps = 0;
  int permissionScreens = 0;

  @override
  Future<InstallBlocker?> blocker() async => block;

  @override
  Future<void> install(File verified) async =>
      installed.add(verified.readAsStringSync());

  @override
  Future<void> cleanUp() async => cleanUps++;

  @override
  Future<void> openPermissionSettings() async => permissionScreens++;
}

const dl = 'https://github.com/devilAPI/stonerspots/releases/download/dev-7';

/// Downloads of the regular release v1.0.1 (fixtures signed with
/// release_v1_key.pub; the Linux entry is SHA-256("test") too).
const dlRelease =
    'https://github.com/devilAPI/stonerspots/releases/download/v1.0.1';

/// Everything the updater talks to, faked. The release dev-7 carries the
/// signed fixture checksums, whose Linux entry is SHA-256("test").
class UpdaterHarness {
  UpdaterHarness({
    this.platform = UpdatePlatform.linux,
    this.build = '6',
    this.version = '1.0.0',
    bool withKey = true,
    String keyFixture = 'release_key.pub',
    String signature = 'SHA256SUMS-apps.txt.sig',
    this.assetBody = 'test',
  }) : key = withKey
           ? SshEd25519PublicKey.parse(fixtureText(keyFixture))
           : null {
    adapter = FakeAdapter({
      releasesApiUrl: (_) => apiAnswer(),
      latestReleaseApiUrl: (_) => latestAnswer(),
      '$dlRelease/SHA256SUMS-apps.txt': (_) =>
          FakeResponse(200, body: fixtureBytes('SHA256SUMS-apps.v1.0.1.txt')),
      '$dlRelease/SHA256SUMS-apps.txt.sig': (_) => FakeResponse(
        200,
        body: fixtureBytes('SHA256SUMS-apps.v1.0.1.txt.sig'),
      ),
      '$dlRelease/stonerspots-v1.0.1-linux-x64.tar.gz': (_) =>
          FakeResponse(200, text: assetBody),
      '$dl/SHA256SUMS-apps.txt': (_) =>
          FakeResponse(200, body: fixtureBytes('SHA256SUMS-apps.txt')),
      '$dl/SHA256SUMS-apps.txt.sig': (_) =>
          FakeResponse(200, body: fixtureBytes(signature)),
      '$dl/stonerspots-dev-7-linux-x64.tar.gz': (_) =>
          FakeResponse(200, text: assetBody),
      '$dl/stonerspots-dev-7-android.apk': (_) =>
          FakeResponse(200, text: assetBody),
    });
  }

  final UpdatePlatform? platform;

  /// Null: a local build without a channel.
  UpdateChannel? channel = UpdateChannel.dev;
  final String build;

  /// The installed version (pubspec `version:` without the build number).
  final String version;
  final SshEd25519PublicKey? key;
  final String assetBody;
  late final FakeAdapter adapter;
  final installer = FakeInstaller();
  final opened = <Uri>[];
  final store = SettingsStore.memory();
  late Directory work;

  FakeResponse Function() apiAnswer = () =>
      FakeResponse(200, text: jsonEncode([ghRelease('dev-7')]));

  /// GitHub's `releases/latest`: one object, never a prerelease.
  FakeResponse Function() latestAnswer = () => FakeResponse(
    200,
    text: jsonEncode(ghRelease('v1.0.1', prerelease: false)),
  );

  List<String> get requested => [
    for (final r in adapter.requests) r.uri.toString(),
  ];

  List<Override> get overrides => [
    settingsStoreProvider.overrideWithValue(store),
    updaterConfigProvider.overrideWithValue(
      UpdaterConfig(channel: channel, platform: platform, signingKey: key),
    ),
    installedVersionLoaderProvider.overrideWithValue(
      () async => InstalledVersion(version: version, buildNumber: build),
    ),
    updaterDioProvider.overrideWithValue(fakeDio(adapter)),
    updateInstallerProvider.overrideWithValue(installer),
    updateWorkDirProvider.overrideWithValue(
      () async => work = Directory.systemTemp.createTempSync('upd'),
    ),
    openExternalUrlProvider.overrideWithValue((u) async => opened.add(u)),
  ];

  ProviderContainer container() => ProviderContainer(overrides: overrides);
}
