/// Releases on GitHub, which of them is newer than this build, and which of
/// their files belongs to this platform.
library;

/// Which releases a build follows. Set at build time with
/// `--dart-define=UPDATE_CHANNEL=dev|release`.
enum UpdateChannel {
  /// Prereleases `dev-<run number>`, compared by run number with the
  /// installed build number.
  dev,

  /// Regular (non-pre)releases tagged `v<major>.<minor>.<patch>`, compared by
  /// version with the installed version.
  release;

  static UpdateChannel? parse(String value) => switch (value.trim()) {
    'dev' => dev,
    'release' => release,
    _ => null,
  };
}

/// Platforms that can update themselves.
enum UpdatePlatform {
  android('-android.apk'),
  linux('-linux-x64.tar.gz'),
  windows('-windows-x64.zip'),
  macos('-macos.zip');

  const UpdatePlatform(this.assetSuffix);

  /// End of the release file name, after `stonerspots-<tag>`.
  final String assetSuffix;
}

/// Signed checksums of the app files of a release (see dev-release.yml).
const appChecksumsName = 'SHA256SUMS-apps.txt';
const appChecksumsSignatureName = 'SHA256SUMS-apps.txt.sig';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;

  /// `browser_download_url`, a `https://github.com/.../releases/download/` URL.
  final String url;
  final int size;

  Map<String, Object?> toJson() => {'name': name, 'url': url, 'size': size};

  static ReleaseAsset? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['browser_download_url'] ?? json['url'];
    final size = json['size'];
    if (name is! String || url is! String || size is! int) return null;
    return ReleaseAsset(name: name, url: url, size: size);
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.prerelease,
    required this.draft,
    required this.htmlUrl,
    required this.assets,
  });

  final String tag;
  final bool prerelease;
  final bool draft;

  /// The release page on github.com.
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  ReleaseAsset? asset(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }

  /// This platform's app file. Only `stonerspots-<this tag><suffix>`
  /// counts: a file named after another tag would be an older build passed
  /// off as this one.
  ReleaseAsset? appAsset(UpdatePlatform platform) =>
      asset('stonerspots-$tag${platform.assetSuffix}');

  Map<String, Object?> toJson() => {
    'tag_name': tag,
    'prerelease': prerelease,
    'draft': draft,
    'html_url': htmlUrl,
    'assets': [for (final a in assets) a.toJson()],
  };

  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final tag = json['tag_name'];
    final htmlUrl = json['html_url'];
    final assets = json['assets'];
    if (tag is! String || htmlUrl is! String) return null;
    return ReleaseInfo(
      tag: tag,
      prerelease: json['prerelease'] == true,
      draft: json['draft'] == true,
      htmlUrl: htmlUrl,
      assets: [
        if (assets is List)
          for (final a in assets) ?ReleaseAsset.fromJson(a),
      ],
    );
  }
}

/// The releases in a GitHub `GET /repos/{owner}/{repo}/releases` answer
/// (or our cached copy of it). Entries that don't parse are left out.
List<ReleaseInfo> parseReleases(Object? json) => [
  if (json is List)
    for (final r in json) ?ReleaseInfo.fromJson(r),
];

/// A plain `major.minor.patch` version; a leading `v` is allowed, a
/// `+build` suffix ignored. Pre-release versions (`2.1.0-beta`) are not
/// versions here.
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final _pattern = RegExp(r'^v?(\d{1,6})\.(\d{1,6})\.(\d{1,6})$');

  static SemVer? tryParse(String text) {
    final core = text.trim().split('+').first;
    final m = _pattern.firstMatch(core);
    if (m == null) return null;
    return SemVer(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}

/// The version of a release tag `vX.Y.Z` (exactly that: the `v`, three
/// numbers, nothing after them), or null. The release workflow refuses any
/// other tag, so anything else is not a release of ours.
SemVer? releaseTagVersion(String tag) =>
    RegExp(r'^v\d{1,6}\.\d{1,6}\.\d{1,6}$').hasMatch(tag)
    ? SemVer.tryParse(tag)
    : null;

/// N of a `dev-N` tag, or null.
int? devRunNumber(String tag) {
  final m = RegExp(r'^dev-(\d{1,9})$').firstMatch(tag);
  return m == null ? null : int.parse(m.group(1)!);
}

/// What is installed: `package_info_plus`'s version and build number.
class InstalledVersion {
  const InstalledVersion({required this.version, required this.buildNumber});

  final String version;

  /// The build number as text; dev builds have the workflow run number.
  final String buildNumber;

  int? get build => int.tryParse(buildNumber.trim());

  @override
  String toString() => '$version+$buildNumber';
}

/// The newest published release of [channel] in [releases], or null.
ReleaseInfo? newestRelease(List<ReleaseInfo> releases, UpdateChannel channel) {
  ReleaseInfo? best;
  for (final r in releases) {
    if (r.draft) continue;
    switch (channel) {
      case UpdateChannel.dev:
        final n = devRunNumber(r.tag);
        if (!r.prerelease || n == null) continue;
        if (best == null || n > devRunNumber(best.tag)!) best = r;
      case UpdateChannel.release:
        final v = releaseTagVersion(r.tag);
        if (r.prerelease || v == null) continue;
        if (best == null || v.compareTo(releaseTagVersion(best.tag)!) > 0) {
          best = r;
        }
    }
  }
  return best;
}

/// Whether [release] is newer than [installed] on [channel]. False when the
/// installed version can't be compared (a local build without a run number).
bool isNewerThanInstalled(
  ReleaseInfo release,
  UpdateChannel channel,
  InstalledVersion installed,
) {
  switch (channel) {
    case UpdateChannel.dev:
      final n = devRunNumber(release.tag);
      final build = installed.build;
      return n != null && build != null && n > build;
    case UpdateChannel.release:
      final v = releaseTagVersion(release.tag);
      final mine = SemVer.tryParse(installed.version);
      return v != null && mine != null && v.compareTo(mine) > 0;
  }
}

/// The update to offer, or null when [releases] has nothing newer on
/// [channel] (or only the version the user chose to skip).
ReleaseInfo? pickUpdate({
  required List<ReleaseInfo> releases,
  required UpdateChannel channel,
  required InstalledVersion installed,
  String? skippedTag,
}) {
  final newest = newestRelease(releases, channel);
  if (newest == null || newest.tag == skippedTag) return null;
  return isNewerThanInstalled(newest, channel, installed) ? newest : null;
}
