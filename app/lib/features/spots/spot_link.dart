import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'browser_share_stub.dart'
    if (dart.library.js_interop) 'browser_share_web.dart';

/// Public address of the web app, used for links shared from the native
/// apps: `--dart-define=WEB_URL=https://.../`.
const String kWebAppUrl = String.fromEnvironment(
  'WEB_URL',
  defaultValue: 'https://devilapi.github.io/stonerspots/',
);

/// Link that opens spot [id] in the web app. In the browser it points at the
/// web app being used (so /dev/ links stay on /dev/), otherwise at
/// [kWebAppUrl]. The web app routes by URL fragment (`#/spot/12`).
Uri spotLink(int id, {Uri? base}) {
  final b = base ?? (kIsWeb ? Uri.base : Uri.parse(kWebAppUrl));
  return Uri(
    scheme: b.scheme,
    host: b.host,
    port: b.hasPort ? b.port : null,
    path: b.path.isEmpty ? '/' : b.path,
    fragment: '/spot/$id',
  );
}

/// Opens the system share sheet for [uri]; false when there is none here
/// (the caller then copies the link instead). [origin] anchors the sheet's
/// popover on iPad and macOS.
typedef LinkSharer = Future<bool> Function(
  Uri uri, {
  String? title,
  Rect? origin,
});

final linkSharerProvider = Provider<LinkSharer>((ref) => shareLink);

Future<bool> shareLink(Uri uri, {String? title, Rect? origin}) async {
  final hasSheet = kIsWeb
      ? browserCanShare(uri)
      : switch (defaultTargetPlatform) {
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.macOS => true,
          _ => false,
        };
  if (!hasSheet) return false;
  await SharePlus.instance.share(
    ShareParams(uri: uri, title: title, sharePositionOrigin: origin),
  );
  return true;
}
