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

/// Everything the updater talks to, faked. The release dev-7 carries the
/// signed fixture checksums, whose Linux entry is SHA-256("test").
class UpdaterHarness {
  UpdaterHarness({
    this.platform = UpdatePlatform.linux,
    this.build = '6',
    bool withKey = true,
    String signature = 'SHA256SUMS-apps.txt.sig',
    this.assetBody = 'test',
  }) : key = withKey
           ? SshEd25519PublicKey.parse(fixtureText('release_key.pub'))
           : null {
    adapter = FakeAdapter({
      releasesApiUrl: (_) => apiAnswer(),
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
  final SshEd25519PublicKey? key;
  final String assetBody;
  late final FakeAdapter adapter;
  final installer = FakeInstaller();
  final opened = <Uri>[];
  final store = SettingsStore.memory();
  late Directory work;

  FakeResponse Function() apiAnswer = () =>
      FakeResponse(200, text: jsonEncode([ghRelease('dev-7')]));

  List<String> get requested => [
    for (final r in adapter.requests) r.uri.toString(),
  ];

  List<Override> get overrides => [
    settingsStoreProvider.overrideWithValue(store),
    updaterConfigProvider.overrideWithValue(
      UpdaterConfig(channel: channel, platform: platform, signingKey: key),
    ),
    installedVersionLoaderProvider.overrideWithValue(
      () async => InstalledVersion(version: '2.0.0', buildNumber: build),
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
