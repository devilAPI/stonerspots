import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether the browser has a share sheet for [uri] (Web Share API: mobile
/// browsers, Safari, Chrome on Windows/ChromeOS). Firefox and Chrome on
/// Linux have none; share_plus would then open an email instead.
bool browserCanShare(Uri uri) {
  final navigator = web.window.navigator;
  if (!navigator.has('canShare')) return false;
  try {
    return navigator.canShare(web.ShareData(url: uri.toString()));
  } catch (_) {
    return false;
  }
}
