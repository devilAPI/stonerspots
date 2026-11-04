import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Release files of this repository: the only URLs the updater starts a
/// download from.
const releaseDownloadPrefix =
    'https://github.com/devilAPI/stonerspots/releases/download/';

/// Hosts a download may be redirected to. GitHub serves release files from
/// release-assets.githubusercontent.com (objects.githubusercontent.com
/// before 2025).
const allowedDownloadHosts = {
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

class DownloadException implements Exception {
  const DownloadException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => 'DownloadException: $message';
}

typedef DownloadProgress = void Function(int received, int? total);

/// Downloads release files over HTTPS from GitHub only: every redirect hop
/// is checked against [allowedHosts], and a body larger than the given cap
/// is cut off.
class SafeDownloader {
  SafeDownloader(
    this._dio, {
    this.allowedHosts = allowedDownloadHosts,
    this.startPrefix = releaseDownloadPrefix,
    this.maxRedirects = 5,
  });

  final Dio _dio;
  final Set<String> allowedHosts;
  final String startPrefix;
  final int maxRedirects;

  void _checkUrl(Uri uri) {
    if (uri.scheme != 'https' ||
        !allowedHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw DownloadException('refusing to download from $uri');
    }
  }

  Future<Response<ResponseBody>> _open(String url, CancelToken? cancel) async {
    if (!url.startsWith(startPrefix)) {
      throw DownloadException('not a release download: $url');
    }
    var uri = Uri.parse(url);
    for (var hop = 0; hop <= maxRedirects; hop++) {
      _checkUrl(uri);
      final Response<ResponseBody> res;
      try {
        res = await _dio.getUri<ResponseBody>(
          uri,
          cancelToken: cancel,
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (_) => true,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
      } on DioException catch (e) {
        throw DownloadException(
          'download failed: ${e.message ?? e.type.name}',
          cancelled: e.type == DioExceptionType.cancel,
        );
      }
      final status = res.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = res.headers.value('location');
        await _drain(res);
        if (location == null) {
          throw const DownloadException('redirect without a location');
        }
        uri = uri.resolve(location);
        continue;
      }
      if (status != 200) {
        await _drain(res);
        throw DownloadException('HTTP $status for $uri');
      }
      return res;
    }
    throw const DownloadException('too many redirects');
  }

  static Future<void> _drain(Response<ResponseBody> res) async {
    try {
      await res.data?.stream.drain<void>();
    } catch (_) {}
  }

  /// Streams [res]'s body to [sink]; stops at [maxBytes] or on [cancel].
  Future<void> _pipe(
    Response<ResponseBody> res,
    void Function(Uint8List chunk) sink, {
    required int maxBytes,
    DownloadProgress? onProgress,
    CancelToken? cancel,
  }) async {
    final length = int.tryParse(res.headers.value('content-length') ?? '');
    if (length != null && length > maxBytes) {
      await _drain(res);
      throw DownloadException('file too large ($length bytes)');
    }
    final body = res.data;
    if (body == null) throw const DownloadException('empty response');
    var received = 0;
    final done = Completer<void>();
    late final StreamSubscription<Uint8List> sub;
    void fail(Object e) {
      if (!done.isCompleted) done.completeError(e);
      sub.cancel();
    }

    sub = body.stream.listen(
      (chunk) {
        received += chunk.length;
        if (received > maxBytes) {
          fail(const DownloadException('file too large'));
          return;
        }
        sink(chunk);
        onProgress?.call(received, length);
      },
      onError: (Object e) => fail(
        e is DownloadException
            ? e
            : DownloadException(
                'download failed: $e',
                cancelled: cancel?.isCancelled ?? false,
              ),
      ),
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    final cancelWatch = cancel?.whenCancel.then(
      (_) => fail(const DownloadException('cancelled', cancelled: true)),
    );
    try {
      await done.future;
    } finally {
      cancelWatch?.ignore();
    }
    if (cancel?.isCancelled ?? false) {
      throw const DownloadException('cancelled', cancelled: true);
    }
    if (length != null && received != length) {
      throw const DownloadException('download incomplete');
    }
  }

  /// A small file (checksums, signature) in memory.
  Future<Uint8List> fetchBytes(
    String url, {
    int maxBytes = 1 << 20,
    CancelToken? cancel,
  }) async {
    final res = await _open(url, cancel);
    final out = BytesBuilder(copy: false);
    await _pipe(res, out.add, maxBytes: maxBytes, cancel: cancel);
    return out.takeBytes();
  }

  /// Downloads [url] into [target]. On any failure [target] is deleted.
  Future<void> download(
    String url,
    File target, {
    required int maxBytes,
    DownloadProgress? onProgress,
    CancelToken? cancel,
  }) async {
    final sink = target.openWrite();
    var closed = false;
    try {
      final res = await _open(url, cancel);
      await _pipe(
        res,
        sink.add,
        maxBytes: maxBytes,
        onProgress: onProgress,
        cancel: cancel,
      );
      await sink.flush();
      await sink.close();
      closed = true;
    } catch (_) {
      if (!closed) {
        try {
          await sink.close();
        } catch (_) {}
      }
      try {
        if (target.existsSync()) target.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }
}
