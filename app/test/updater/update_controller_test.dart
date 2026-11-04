import 'dart:convert';

import 'package:app/features/updater/installer.dart';
import 'package:app/features/updater/release.dart';
import 'package:app/features/updater/release_source.dart';
import 'package:app/features/updater/update_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';
import 'updater_harness.dart';

void main() {
  ProviderContainer start(UpdaterHarness h) {
    final c = h.container();
    addTearDown(c.dispose);
    return c;
  }

  UpdateController ctl(ProviderContainer c) =>
      c.read(updateControllerProvider.notifier);

  test('finds the newer dev build at start', () async {
    final h = UpdaterHarness();
    final c = start(h);
    await ctl(c).onAppStart();
    final s = c.read(updateControllerProvider);
    expect(s.stage, UpdateStage.available);
    expect(s.release?.tag, 'dev-7');
    expect(s.showBanner, isTrue);
    expect(s.installBlocked, isNull);
    expect(h.installer.cleanUps, 1);
  });

  test('nothing newer: no banner', () async {
    final h = UpdaterHarness(build: '7');
    final c = start(h);
    await ctl(c).onAppStart();
    expect(c.read(updateControllerProvider).stage, UpdateStage.upToDate);
    expect(c.read(updateControllerProvider).showBanner, isFalse);
  });

  test('automatic checks off: GitHub is not asked', () async {
    final h = UpdaterHarness();
    final c = start(h);
    c.read(autoUpdateCheckProvider.notifier).set(false);
    await ctl(c).onAppStart();
    expect(h.requested, isEmpty);
    expect(h.installer.cleanUps, 1); // leftovers still go
    // the settings button still works
    await ctl(c).checkNow();
    expect(c.read(updateControllerProvider).release?.tag, 'dev-7');
  });

  test('automatic checks are on by default', () {
    final c = start(UpdaterHarness());
    expect(c.read(autoUpdateCheckProvider), isTrue);
  });

  test('a rate limit at start stays quiet', () async {
    final h = UpdaterHarness()
      ..apiAnswer = () => FakeResponse(403, headers: {'retry-after': '60'});
    final c = start(h);
    await ctl(c).onAppStart();
    final s = c.read(updateControllerProvider);
    expect(s.stage, UpdateStage.idle);
    expect(s.showBanner, isFalse);
    expect(s.problem, UpdateProblem.rateLimited);
  });

  test('skip remembers the version; a manual check shows it again', () async {
    final h = UpdaterHarness();
    var c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).skip();
    expect(c.read(updateControllerProvider).showBanner, isFalse);

    c = start(h); // next start, same storage
    await ctl(c).onAppStart();
    expect(c.read(updateControllerProvider).showBanner, isFalse);

    await ctl(c).checkNow();
    expect(c.read(updateControllerProvider).release?.tag, 'dev-7');
  });

  test('later hides the banner for this session only', () async {
    final h = UpdaterHarness();
    final c = start(h);
    await ctl(c).onAppStart();
    ctl(c).later();
    expect(c.read(updateControllerProvider).showBanner, isFalse);
    await ctl(c).checkNow();
    expect(c.read(updateControllerProvider).showBanner, isTrue);
  });

  test('verified update: downloads, checks and installs', () async {
    final h = UpdaterHarness();
    final c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).updateNow();
    expect(h.installer.installed, ['test']);
    expect(c.read(updateControllerProvider).stage, UpdateStage.handedOff);
    expect(h.requested, [
      releasesApiUrl,
      '$dl/SHA256SUMS-apps.txt',
      '$dl/SHA256SUMS-apps.txt.sig',
      '$dl/stonerspots-dev-7-linux-x64.tar.gz',
    ]);
    expect(h.work.existsSync(), isFalse); // desktop: temp folder removed
  });

  test('cancel during the download: back to "available"', () async {
    final h = UpdaterHarness();
    final c = start(h);
    h.adapter.routes['$dl/stonerspots-dev-7-linux-x64.tar.gz'] = (_) =>
        FakeResponse(200, text: 'x' * 1000, chunkSize: 10);
    h.adapter.onChunk = (sent) {
      if (sent == 100) ctl(c).cancel();
    };
    await ctl(c).onAppStart();
    final progress = <double?>[];
    c.listen(updateControllerProvider, (_, s) => progress.add(s.progress));
    await ctl(c).updateNow();
    final s = c.read(updateControllerProvider);
    expect(s.stage, UpdateStage.available);
    expect(s.problem, isNull);
    expect(h.installer.installed, isEmpty);
    expect(progress.whereType<double>(), isNotEmpty);
  });

  test(
    'no key compiled in: only the release page, nothing downloaded',
    () async {
      final h = UpdaterHarness(withKey: false);
      final c = start(h);
      await ctl(c).onAppStart();
      expect(
        c.read(updateControllerProvider).installBlocked,
        UpdateProblem.noSigningKey,
      );
      await ctl(c).updateNow();
      expect(h.opened, [
        Uri.parse('https://github.com/devilAPI/stonerspots/releases/tag/dev-7'),
      ]);
      expect(h.installer.installed, isEmpty);
      expect(h.requested, [releasesApiUrl]);
    },
  );

  test('folder not writable: the release page instead', () async {
    final h = UpdaterHarness();
    h.installer.block = InstallBlocker.notWritable;
    final c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).updateNow();
    expect(h.opened, hasLength(1));
    expect(h.installer.installed, isEmpty);
    expect(h.requested, [releasesApiUrl]);
  });

  test('a signature by another key: nothing installed, file not even '
      'downloaded', () async {
    final h = UpdaterHarness(signature: 'SHA256SUMS-apps.other-key.sig');
    final c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).updateNow();
    final s = c.read(updateControllerProvider);
    expect(s.stage, UpdateStage.failed);
    expect(s.problem, UpdateProblem.signatureInvalid);
    expect(h.installer.installed, isEmpty);
    expect(h.requested, isNot(contains(endsWith('.tar.gz'))));
  });

  test('wrong namespace: refused', () async {
    final h = UpdaterHarness(signature: 'SHA256SUMS-apps.wrong-namespace.sig');
    final c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).updateNow();
    expect(
      c.read(updateControllerProvider).problem,
      UpdateProblem.signatureInvalid,
    );
    expect(h.installer.installed, isEmpty);
  });

  test(
    'a file that does not match the signed checksum is not installed',
    () async {
      final h = UpdaterHarness(assetBody: 'tesT');
      final c = start(h);
      await ctl(c).onAppStart();
      await ctl(c).updateNow();
      final s = c.read(updateControllerProvider);
      expect(s.problem, UpdateProblem.checksumMismatch);
      expect(h.installer.installed, isEmpty);
      expect(h.work.existsSync(), isFalse);
    },
  );

  test('a file the signed checksums do not list is not installed', () async {
    // the fixture lists the APK with a hash no body here matches; and the
    // Windows zip not at all
    final h = UpdaterHarness(platform: UpdatePlatform.windows);
    final c = start(h);
    await ctl(c).onAppStart();
    await ctl(c).updateNow();
    expect(
      c.read(updateControllerProvider).problem,
      anyOf(UpdateProblem.signatureInvalid, UpdateProblem.assetMissing),
    );
    expect(h.installer.installed, isEmpty);
  });

  test(
    'Android without "install unknown apps": guide to the setting',
    () async {
      final h = UpdaterHarness(platform: UpdatePlatform.android);
      h.installer.block = InstallBlocker.needsInstallPermission;
      final c = start(h);
      await ctl(c).onAppStart();
      await ctl(c).updateNow();
      expect(
        c.read(updateControllerProvider).problem,
        UpdateProblem.needsInstallPermission,
      );
      expect(h.requested, [releasesApiUrl]);
      await ctl(c).openInstallPermissionSettings();
      expect(h.installer.permissionScreens, 1);
    },
  );

  test('a build without a channel never checks', () async {
    final h = UpdaterHarness()..channel = null;
    final c = start(h);
    expect(c.read(updaterConfigProvider).enabled, isFalse);
    await ctl(c).onAppStart();
    await ctl(c).checkNow();
    expect(h.requested, isEmpty);
    expect(h.installer.cleanUps, 0);
  });

  group('release channel', () {
    UpdaterHarness releaseHarness({String version = '1.0.0'}) => UpdaterHarness(
      version: version,
      build: '480',
      keyFixture: 'release_v1_key.pub',
    )..channel = UpdateChannel.release;

    test('asks for the latest release only, not the dev list', () async {
      final h = releaseHarness();
      final c = start(h);
      await ctl(c).onAppStart();
      final s = c.read(updateControllerProvider);
      expect(s.stage, UpdateStage.available);
      expect(s.release?.tag, 'v1.0.1');
      expect(h.requested, [latestReleaseApiUrl]);
    });

    test('the same or an older version is not offered', () async {
      for (final v in ['1.0.1', '1.1.0', '2.0.0']) {
        final h = releaseHarness(version: v);
        final c = start(h);
        await ctl(c).checkNow();
        expect(
          c.read(updateControllerProvider).stage,
          UpdateStage.upToDate,
          reason: v,
        );
      }
    });

    test('no release published yet (404): up to date, not offline', () async {
      final h = releaseHarness()
        ..latestAnswer = () =>
            FakeResponse(404, text: '{"message":"Not Found"}');
      final c = start(h);
      await ctl(c).checkNow();
      final s = c.read(updateControllerProvider);
      expect(s.stage, UpdateStage.upToDate);
      expect(s.problem, isNull);
    });

    test('a dev build or a stray tag as "latest" is ignored', () async {
      for (final tag in ['dev-500', '1.0.2', 'v1.0.2-rc1', 'v1.0']) {
        final h = releaseHarness()
          ..latestAnswer = () => FakeResponse(
            200,
            text: jsonEncode(ghRelease(tag, prerelease: false)),
          );
        final c = start(h);
        await ctl(c).checkNow();
        expect(
          c.read(updateControllerProvider).stage,
          UpdateStage.upToDate,
          reason: tag,
        );
      }
    });

    test('verified update of stonerspots-v1.0.1-linux-x64.tar.gz', () async {
      final h = releaseHarness();
      final c = start(h);
      await ctl(c).onAppStart();
      await ctl(c).updateNow();
      expect(c.read(updateControllerProvider).stage, UpdateStage.handedOff);
      expect(h.installer.installed, ['test']);
      expect(h.requested, [
        latestReleaseApiUrl,
        '$dlRelease/SHA256SUMS-apps.txt',
        '$dlRelease/SHA256SUMS-apps.txt.sig',
        '$dlRelease/stonerspots-v1.0.1-linux-x64.tar.gz',
      ]);
    });

    test('checksums signed with another key are refused', () async {
      final h =
          UpdaterHarness(version: '1.0.0') // the dev fixtures' key
            ..channel = UpdateChannel.release;
      final c = start(h);
      await ctl(c).onAppStart();
      await ctl(c).updateNow();
      expect(
        c.read(updateControllerProvider).problem,
        UpdateProblem.signatureInvalid,
      );
      expect(h.installer.installed, isEmpty);
    });
  });

  test('the release page is built from the tag', () {
    expect(
      releasePageUrl('dev-7').toString(),
      'https://github.com/devilAPI/stonerspots/releases/tag/dev-7',
    );
    expect(releasePageUrl('../x').path, isNot(contains('/../')));
  });
}
