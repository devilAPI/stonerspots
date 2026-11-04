import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/settings.dart';
import 'release.dart';

/// Where releases are listed. Unauthenticated: 60 requests an hour per IP,
/// and conditional requests answered with 304 don't count.
const releasesApiUrl =
    'https://api.github.com/repos/devilAPI/stonerspots/releases?per_page=30';

/// The newest regular release alone (GitHub's "latest": never a draft or a
/// prerelease). The release channel asks here, because in the list above a
/// release drops off the first page after 30 dev builds.
const latestReleaseApiUrl =
    'https://api.github.com/repos/devilAPI/stonerspots/releases/latest';

/// Where [channel] looks for updates.
String releasesApiUrlFor(UpdateChannel channel) => switch (channel) {
  UpdateChannel.dev => releasesApiUrl,
  UpdateChannel.release => latestReleaseApiUrl,
};

/// The release list and how fresh it is.
class ReleaseListResult {
  const ReleaseListResult({
    required this.releases,
    this.fromCache = false,
    this.rateLimited = false,
    this.failed = false,
  });

  /// Null when there is neither a fresh answer nor a cached one.
  final List<ReleaseInfo>? releases;
  final bool fromCache;

  /// GitHub said to come back later; [releases] is the cached list, if any.
  final bool rateLimited;

  /// The request failed (offline, server error, junk); [releases] is the
  /// cached list, if any.
  final bool failed;
}

/// Reads the GitHub release list at most once per [minInterval] (unless
/// forced), remembers it with its ETag, and backs off quietly while GitHub
/// rate-limits us.
class ReleaseSource {
  ReleaseSource({
    required this._dio,
    required this._store,
    DateTime Function()? now,
    this.minInterval = const Duration(hours: 6),
    this.url = releasesApiUrl,
  }) : _now = now ?? DateTime.now;

  final Dio _dio;
  final SettingsStore _store;
  final DateTime Function() _now;
  final Duration minInterval;
  final String url;

  static const _bodyKey = 'updater.releases';
  static const _etagKey = 'updater.releases_etag';
  static const _fetchedKey = 'updater.releases_fetched_ms';
  static const _retryKey = 'updater.retry_after_ms';
  static const _urlKey = 'updater.releases_url';

  /// [url] answers with one release object (`/releases/latest`), not a list.
  bool get _single => url.endsWith('/releases/latest');

  List<ReleaseInfo>? _cached() {
    final body = _store.getString(_bodyKey);
    if (body == null) return null;
    // a list fetched from another URL (an app of the other channel was
    // installed over this one) is not this channel's
    if (_store.getString(_urlKey) != url) return null;
    try {
      return parseReleases(jsonDecode(body));
    } on FormatException {
      return null;
    }
  }

  /// Whether an automatic check would ask GitHub now.
  bool get isDue {
    final fetched = _store.getInt(_fetchedKey);
    final now = _now().millisecondsSinceEpoch;
    if (now < (_store.getInt(_retryKey) ?? 0)) return false;
    return fetched == null ||
        _cached() == null ||
        now - fetched >= minInterval.inMilliseconds ||
        now < fetched; // clock went back
  }

  /// The release list. Without [force], a list younger than [minInterval]
  /// comes from the cache. A rate limit is honoured even when forced.
  Future<ReleaseListResult> releases({bool force = false}) async {
    final cached = _cached();
    final now = _now().millisecondsSinceEpoch;
    if (now < (_store.getInt(_retryKey) ?? 0)) {
      return ReleaseListResult(
        releases: cached,
        fromCache: true,
        rateLimited: true,
      );
    }
    if (!force && !isDue && cached != null) {
      return ReleaseListResult(releases: cached, fromCache: true);
    }

    final etag = cached == null ? null : _store.getString(_etagKey);
    final Response<String> res;
    try {
      res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (_) => true,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'If-None-Match': ?etag,
          },
        ),
      );
    } on DioException {
      return ReleaseListResult(releases: cached, fromCache: true, failed: true);
    }

    final status = res.statusCode ?? 0;
    if (status == 304 && cached != null) {
      await _store.setInt(_fetchedKey, now);
      return ReleaseListResult(releases: cached, fromCache: true);
    }
    if (status == 403 || status == 429) {
      await _store.setInt(_retryKey, _retryAt(res.headers, now));
      return ReleaseListResult(
        releases: cached,
        fromCache: true,
        rateLimited: true,
      );
    }
    final List<ReleaseInfo> fresh;
    if (status == 404 && _single) {
      fresh = const []; // no release published yet
    } else if (status != 200) {
      return ReleaseListResult(releases: cached, fromCache: true, failed: true);
    } else {
      try {
        var json = jsonDecode(res.data ?? '');
        if (_single && json is Map) json = [json];
        if (json is! List) throw const FormatException('not a list');
        fresh = parseReleases(json);
      } on FormatException {
        return ReleaseListResult(
          releases: cached,
          fromCache: true,
          failed: true,
        );
      }
    }
    // Only what the updater needs, not GitHub's whole answer.
    await _store.setString(
      _bodyKey,
      jsonEncode([for (final r in fresh) r.toJson()]),
    );
    await _store.setString(_urlKey, url);
    await _store.setString(_etagKey, res.headers.value('etag'));
    await _store.setInt(_fetchedKey, now);
    await _store.setInt(_retryKey, null);
    return ReleaseListResult(releases: fresh);
  }

  /// When to ask again after a 403/429: `retry-after` (seconds), else
  /// `x-ratelimit-reset` (epoch seconds), else in an hour. At most a day.
  static int _retryAt(Headers headers, int now) {
    const hour = 60 * 60 * 1000;
    int? at;
    final after = int.tryParse(headers.value('retry-after') ?? '');
    if (after != null) at = now + after * 1000;
    final reset = int.tryParse(headers.value('x-ratelimit-reset') ?? '');
    if (at == null && reset != null) at = reset * 1000;
    if (at == null || at <= now) at = now + hour;
    return at.clamp(now, now + 24 * hour);
  }
}
