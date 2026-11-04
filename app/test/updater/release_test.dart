import 'dart:convert';

import 'package:app/features/updater/release.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('parses the GitHub release list and skips junk entries', () {
    final json = jsonDecode(
      jsonEncode([
        ghRelease('dev-63'),
        {'tag_name': 5},
        'nonsense',
        ghRelease('v2.1.0', prerelease: false),
      ]),
    );
    final releases = parseReleases(json);
    expect(releases.map((r) => r.tag), ['dev-63', 'v2.1.0']);
    final r = releases.first;
    expect(r.prerelease, isTrue);
    expect(r.assets, hasLength(6));
    expect(
      r.appAsset(UpdatePlatform.android)?.url,
      'https://github.com/devilAPI/stonerspots/releases/download/dev-63/stonerspots-dev-63-android.apk',
    );
    expect(
      r.appAsset(UpdatePlatform.windows)?.name,
      'stonerspots-dev-63-windows-x64.zip',
    );
    expect(r.asset(appChecksumsSignatureName), isNotNull);
    expect(parseReleases({'message': 'API rate limit exceeded'}), isEmpty);

    // our cache format round-trips
    final again = parseReleases(jsonDecode(jsonEncode([r.toJson()])));
    expect(again.single.appAsset(UpdatePlatform.linux)?.size, 1234);
  });

  test('a file named after another tag is not this release\'s', () {
    final r = ReleaseInfo.fromJson(
      ghRelease('dev-99', assets: ['stonerspots-dev-50-android.apk']),
    )!;
    expect(r.appAsset(UpdatePlatform.android), isNull);
  });

  test('versions', () {
    expect(SemVer.tryParse('v2.1.0').toString(), '2.1.0');
    expect(SemVer.tryParse('2.0.0+63').toString(), '2.0.0');
    expect(SemVer.tryParse('2.1.0-beta'), isNull);
    expect(SemVer.tryParse('dev-63'), isNull);
    expect(SemVer.tryParse('2.1'), isNull);
    expect(SemVer.tryParse('2.10.0')!.compareTo(SemVer.tryParse('2.9.9')!), 1);
    expect(SemVer.tryParse('3.0.0')!.compareTo(SemVer.tryParse('2.99.99')!), 1);
    expect(SemVer.tryParse('2.0.1')!.compareTo(SemVer.tryParse('v2.0.1')!), 0);
    expect(devRunNumber('dev-63'), 63);
    expect(devRunNumber('dev-'), isNull);
    expect(devRunNumber('dev-6x'), isNull);
    expect(devRunNumber('v1.0.0'), isNull);
  });

  final releases = parseReleases(
    jsonDecode(
      jsonEncode([
        ghRelease('dev-9'), // listed first, but older than dev-10
        ghRelease('dev-10'),
        ghRelease('dev-11', draft: true),
        ghRelease('dev-12', prerelease: false), // not a dev build
        ghRelease('v2.0.0', prerelease: false),
        ghRelease('v2.10.0', prerelease: false),
        ghRelease('v2.9.0', prerelease: false),
        ghRelease('v3.0.0', prerelease: true), // a prerelease
        ghRelease('nightly'),
      ]),
    ),
  );

  test('the newest of each channel', () {
    expect(newestRelease(releases, UpdateChannel.dev)?.tag, 'dev-10');
    expect(newestRelease(releases, UpdateChannel.release)?.tag, 'v2.10.0');
    expect(newestRelease(const [], UpdateChannel.dev), isNull);
  });

  test('dev builds compare run number with build number', () {
    InstalledVersion v(String build) =>
        InstalledVersion(version: '2.0.0', buildNumber: build);
    ReleaseInfo? pick(String build, {String? skipped}) => pickUpdate(
      releases: releases,
      channel: UpdateChannel.dev,
      installed: v(build),
      skippedTag: skipped,
    );
    expect(pick('9')?.tag, 'dev-10');
    expect(pick('10'), isNull);
    expect(pick('63'), isNull);
    expect(pick(''), isNull); // a local build has no comparable number
    expect(pick('9', skipped: 'dev-10'), isNull);
    expect(pick('9', skipped: 'dev-8')?.tag, 'dev-10');
  });

  test('release builds compare versions', () {
    ReleaseInfo? pick(String version) => pickUpdate(
      releases: releases,
      channel: UpdateChannel.release,
      installed: InstalledVersion(version: version, buildNumber: '2'),
    );
    expect(pick('2.0.0')?.tag, 'v2.10.0');
    expect(pick('2.9.5')?.tag, 'v2.10.0');
    expect(pick('2.10.0'), isNull);
    expect(pick('3.0.0'), isNull); // the 3.0.0 prerelease doesn't count
    expect(pick('weird'), isNull);
  });

  test('release tags are exactly vX.Y.Z', () {
    expect(releaseTagVersion('v1.0.0').toString(), '1.0.0');
    expect(releaseTagVersion('v10.20.30').toString(), '10.20.30');
    for (final tag in [
      '1.0.0', // no v
      'v1.0',
      'v1.0.0-rc1',
      'v1.0.0+5',
      'V1.0.0',
      ' v1.0.0',
      'dev-63',
      'release-1.0.0',
    ]) {
      expect(releaseTagVersion(tag), isNull, reason: tag);
    }
  });

  test('release channel: v1.0.0 among many dev builds', () {
    final list = parseReleases(
      jsonDecode(
        jsonEncode([
          for (var n = 500; n > 470; n--) ghRelease('dev-$n'),
          ghRelease('v1.0.0', prerelease: false),
          ghRelease('1.5.0', prerelease: false), // not our tag form
          ghRelease('v1.1.0-rc1', prerelease: false),
          ghRelease('dev-900', prerelease: false), // dev, marked wrongly
        ]),
      ),
    );
    expect(newestRelease(list, UpdateChannel.release)?.tag, 'v1.0.0');
    expect(newestRelease(list, UpdateChannel.dev)?.tag, 'dev-500');
    ReleaseInfo? pick(String version, String build) => pickUpdate(
      releases: list,
      channel: UpdateChannel.release,
      installed: InstalledVersion(version: version, buildNumber: build),
    );
    // a release build of 0.9.0 is offered 1.0.0, whatever its build number
    expect(pick('0.9.0', '999')?.tag, 'v1.0.0');
    expect(pick('1.0.0', '480'), isNull);
    expect(pick('1.0.1', '481'), isNull);
    // 1.0.0's file names carry its tag
    expect(
      newestRelease(
        list,
        UpdateChannel.release,
      )!.appAsset(UpdatePlatform.android)?.name,
      'stonerspots-v1.0.0-android.apk',
    );
  });

  test('channel names', () {
    expect(UpdateChannel.parse('dev'), UpdateChannel.dev);
    expect(UpdateChannel.parse('release'), UpdateChannel.release);
    expect(UpdateChannel.parse(''), isNull);
    expect(UpdateChannel.parse('beta'), isNull);
  });
}
