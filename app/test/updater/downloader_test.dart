import 'dart:io';

import 'package:app/features/updater/downloader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const start =
    'https://github.com/devilAPI/stonerspots/releases/download/dev-7/a.apk';
const cdn = 'https://release-assets.githubusercontent.com/x/a.apk?sig=1';

void main() {
  late Directory dir;
  late File target;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dl');
    target = File('${dir.path}/a.apk');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FakeResponse redirect(String to) =>
      FakeResponse(302, headers: {'location': to});

  test('follows GitHub\'s redirect and reports progress', () async {
    final body = List.generate(1000, (i) => i % 256);
    final adapter = FakeAdapter({
      start: (_) => redirect(cdn),
      cdn: (_) => FakeResponse(
        200,
        body: body,
        chunkSize: 100,
        headers: {'content-length': '1000'},
      ),
    });
    final seen = <int>[];
    await SafeDownloader(fakeDio(adapter)).download(
      start,
      target,
      maxBytes: 5000,
      onProgress: (r, _) => seen.add(r),
    );
    expect(target.readAsBytesSync(), body);
    expect(seen.last, 1000);
    expect(seen, hasLength(10));
    // every hop by hand: Dio must not follow on its own
    expect(adapter.requests.every((r) => r.followRedirects == false), isTrue);
  });

  test('only release downloads of this repository are started', () async {
    final d = SafeDownloader(fakeDio(FakeAdapter({})));
    for (final url in [
      'https://github.com/someone/else/releases/download/x/a.apk',
      'http://github.com/devilAPI/stonerspots/releases/download/x/a.apk',
      'https://evil.example/devilAPI/stonerspots/releases/download/x/a.apk',
    ]) {
      await expectLater(
        d.download(url, target, maxBytes: 10),
        throwsA(isA<DownloadException>()),
        reason: url,
      );
    }
  });

  test('a redirect off GitHub, or to plain HTTP, is refused', () async {
    for (final to in [
      'https://evil.example/a.apk',
      'http://release-assets.githubusercontent.com/a.apk',
      'https://user@release-assets.githubusercontent.com/a.apk',
      'https://release-assets.githubusercontent.com:8443/a.apk',
      'https://github.com.evil.example/a.apk',
    ]) {
      final adapter = FakeAdapter({
        start: (_) => redirect(to),
        to: (_) => FakeResponse(200, text: 'evil'),
      });
      await expectLater(
        SafeDownloader(fakeDio(adapter)).download(start, target, maxBytes: 10),
        throwsA(isA<DownloadException>()),
        reason: to,
      );
      expect(adapter.requests, hasLength(1), reason: to);
      expect(target.existsSync(), isFalse);
    }
  });

  test('redirect loops end', () async {
    final adapter = FakeAdapter({start: (_) => redirect(start)});
    await expectLater(
      SafeDownloader(fakeDio(adapter)).download(start, target, maxBytes: 10),
      throwsA(isA<DownloadException>()),
    );
    expect(adapter.requests.length, lessThanOrEqualTo(6));
  });

  test('a file over the cap is cut off and deleted', () async {
    // by its announced length
    var adapter = FakeAdapter({
      start: (_) => FakeResponse(
        200,
        body: List.filled(100, 1),
        headers: {'content-length': '100'},
      ),
    });
    await expectLater(
      SafeDownloader(fakeDio(adapter)).download(start, target, maxBytes: 50),
      throwsA(isA<DownloadException>()),
    );
    expect(target.existsSync(), isFalse);

    // and without one
    adapter = FakeAdapter({
      start: (_) => FakeResponse(200, body: List.filled(100, 1), chunkSize: 10),
    });
    await expectLater(
      SafeDownloader(fakeDio(adapter)).download(start, target, maxBytes: 50),
      throwsA(isA<DownloadException>()),
    );
    expect(target.existsSync(), isFalse);
  });

  test('HTTP errors fail', () async {
    final adapter = FakeAdapter({start: (_) => FakeResponse(404)});
    await expectLater(
      SafeDownloader(fakeDio(adapter)).fetchBytes(start),
      throwsA(isA<DownloadException>()),
    );
  });

  test('cancel stops the download and removes the file', () async {
    final cancel = CancelToken();
    final adapter =
        FakeAdapter({
            start: (_) =>
                FakeResponse(200, body: List.filled(1000, 1), chunkSize: 10),
          })
          ..onChunk = (sent) {
            if (sent >= 300) cancel.cancel();
          };
    await expectLater(
      SafeDownloader(fakeDio(adapter))
          .download(start, target, maxBytes: 5000, cancel: cancel),
      throwsA(
        isA<DownloadException>().having((e) => e.cancelled, 'cancelled', true),
      ),
    );
    expect(target.existsSync(), isFalse);
  });
}
