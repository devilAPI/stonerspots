import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned HTTP answer.
class FakeResponse {
  FakeResponse(
    this.status, {
    List<int>? body,
    String? text,
    this.headers = const {},
    this.chunkSize,
  }) : body = Uint8List.fromList(body ?? utf8.encode(text ?? ''));

  final int status;
  final Uint8List body;
  final Map<String, String> headers;

  /// Sends the body in chunks of this size (for progress / cancel tests).
  final int? chunkSize;
}

/// Answers Dio requests from a URL -> response table and records them.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.routes);

  final Map<String, FakeResponse Function(RequestOptions)> routes;
  final requests = <RequestOptions>[];

  /// Called between chunks; lets a test cancel mid-download.
  void Function(int sent)? onChunk;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes[options.uri.toString()];
    if (handler == null) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route for ${options.uri}',
      );
    }
    final r = handler(options);
    final headers = {
      for (final e in r.headers.entries) e.key.toLowerCase(): [e.value],
    };
    final size = r.chunkSize;
    if (size == null) {
      return ResponseBody.fromBytes(r.body, r.status, headers: headers);
    }
    final controller = StreamController<Uint8List>();
    var cancelled = false;
    cancelFuture?.then((_) => cancelled = true);
    () async {
      for (var i = 0; i < r.body.length && !cancelled; i += size) {
        final end = (i + size).clamp(0, r.body.length);
        controller.add(Uint8List.sublistView(r.body, i, end));
        onChunk?.call(end);
        await Future<void>.delayed(Duration.zero);
      }
      await controller.close();
    }();
    return ResponseBody(controller.stream, r.status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Dio fakeDio(FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;

/// Reads a fixture next to this file.
String fixturePath(String name) =>
    '${Directory.current.path}/test/updater/fixtures/$name';

Uint8List fixtureBytes(String name) =>
    File(fixturePath(name)).readAsBytesSync();

String fixtureText(String name) => File(fixturePath(name)).readAsStringSync();

/// A trimmed GitHub answer, in its real shape.
Map<String, Object?> ghRelease(
  String tag, {
  bool prerelease = true,
  bool draft = false,
  List<String>? assets,
}) => {
  'url': 'https://api.github.com/repos/devilAPI/stonerspots/releases/1',
  'html_url': 'https://github.com/devilAPI/stonerspots/releases/tag/$tag',
  'id': 1,
  'tag_name': tag,
  'name': 'Dev build',
  'draft': draft,
  'prerelease': prerelease,
  'published_at': '2026-11-02T06:23:03Z',
  'assets': [
    for (final name
        in assets ??
            [
              'SHA256SUMS-apps.txt',
              'SHA256SUMS-apps.txt.sig',
              'stonerspots-$tag-android.apk',
              'stonerspots-$tag-linux-x64.tar.gz',
              'stonerspots-$tag-windows-x64.zip',
              'stonerspots-$tag-macos.zip',
            ])
      {
        'name': name,
        'size': 1234,
        'uploader': {'login': 'github-actions[bot]'},
        'browser_download_url':
            'https://github.com/devilAPI/stonerspots/releases/download/$tag/$name',
      },
  ],
};
