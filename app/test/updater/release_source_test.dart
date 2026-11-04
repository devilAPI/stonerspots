import 'dart:convert';

import 'package:app/core/settings.dart';
import 'package:app/features/updater/release_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late SettingsStore store;
  late DateTime now;
  late FakeResponse Function() answer;
  late FakeAdapter adapter;
  late ReleaseSource source;

  setUp(() {
    store = SettingsStore.memory();
    now = DateTime.utc(2026, 11, 4, 12);
    answer = () => FakeResponse(
      200,
      text: jsonEncode([ghRelease('dev-63')]),
      headers: {'etag': 'W/"abc"'},
    );
    adapter = FakeAdapter({releasesApiUrl: (_) => answer()});
    source = ReleaseSource(dio: fakeDio(adapter), store: store, now: () => now);
  });

  test('asks GitHub once, then answers from the cache for 6 hours', () async {
    final first = await source.releases();
    expect(first.releases!.single.tag, 'dev-63');
    expect(first.fromCache, isFalse);
    expect(adapter.requests, hasLength(1));
    expect(
      adapter.requests.single.headers['Accept'],
      'application/vnd.github+json',
    );

    now = now.add(const Duration(hours: 5, minutes: 59));
    expect(source.isDue, isFalse);
    final cached = await source.releases();
    expect(cached.fromCache, isTrue);
    expect(cached.releases!.single.tag, 'dev-63');
    expect(adapter.requests, hasLength(1));

    now = now.add(const Duration(minutes: 1));
    expect(source.isDue, isTrue);
    await source.releases();
    expect(adapter.requests, hasLength(2));
  });

  test('a forced check asks at once, with the ETag', () async {
    await source.releases();
    answer = () => FakeResponse(304);
    final r = await source.releases(force: true);
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.headers['If-None-Match'], 'W/"abc"');
    expect(r.releases!.single.tag, 'dev-63'); // 304: the cached list
  });

  test('a rate limit is honoured quietly, even when forced', () async {
    await source.releases();
    now = now.add(const Duration(hours: 7));
    final reset = now.add(const Duration(minutes: 30));
    answer = () => FakeResponse(
      403,
      text: '{"message":"API rate limit exceeded"}',
      headers: {
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
      },
    );
    final limited = await source.releases();
    expect(limited.rateLimited, isTrue);
    expect(limited.releases!.single.tag, 'dev-63'); // still the cached list
    expect(adapter.requests, hasLength(2));

    // until the reset, nothing goes out, forced or not
    answer = () => FakeResponse(200, text: jsonEncode([ghRelease('dev-64')]));
    expect((await source.releases(force: true)).rateLimited, isTrue);
    expect((await source.releases()).rateLimited, isTrue);
    expect(adapter.requests, hasLength(2));

    now = reset.add(const Duration(seconds: 1));
    final after = await source.releases();
    expect(after.rateLimited, isFalse);
    expect(after.releases!.single.tag, 'dev-64');
    expect(adapter.requests, hasLength(3));
  });

  test('429 with retry-after', () async {
    answer = () => FakeResponse(429, headers: {'retry-after': '120'});
    final r = await source.releases();
    expect(r.rateLimited, isTrue);
    expect(r.releases, isNull); // nothing cached yet
    now = now.add(const Duration(seconds: 119));
    await source.releases(force: true);
    expect(adapter.requests, hasLength(1));
    now = now.add(const Duration(seconds: 2));
    await source.releases(force: true);
    expect(adapter.requests, hasLength(2));
  });

  test('offline or junk: the cached list, marked as failed', () async {
    await source.releases();
    adapter.routes.clear(); // connection errors from now on
    final offline = await source.releases(force: true);
    expect(offline.failed, isTrue);
    expect(offline.releases!.single.tag, 'dev-63');

    adapter.routes[releasesApiUrl] = (_) => FakeResponse(200, text: '<html>');
    final junk = await source.releases(force: true);
    expect(junk.failed, isTrue);
    expect(junk.releases!.single.tag, 'dev-63');

    adapter.routes[releasesApiUrl] = (_) => FakeResponse(500);
    expect((await source.releases(force: true)).failed, isTrue);
  });

  test('keeps only what the updater needs', () async {
    await source.releases();
    final cached = store.getString('updater.releases')!;
    expect(cached, isNot(contains('uploader')));
    expect(cached, contains('stonerspots-dev-63-android.apk'));
  });
}
