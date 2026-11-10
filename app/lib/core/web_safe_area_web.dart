import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// A hidden element whose padding is the safe area: CSS knows it
/// (`env(safe-area-inset-*)`, with `viewport-fit=cover`), Dart only through
/// the computed style.
web.HTMLElement? _probe;

web.HTMLElement _element() => _probe ??= () {
  final e = web.document.createElement('div') as web.HTMLElement;
  e.style.cssText =
      'position:fixed;top:0;left:0;width:0;height:0;visibility:hidden;'
      'pointer-events:none;'
      'padding-top:env(safe-area-inset-top,0px);'
      'padding-right:env(safe-area-inset-right,0px);'
      'padding-bottom:env(safe-area-inset-bottom,0px);'
      'padding-left:env(safe-area-inset-left,0px);';
  web.document.body?.append(e);
  return e;
}();

double _px(String v) => double.tryParse(v.replaceAll('px', '').trim()) ?? 0;

EdgeInsets readWebSafeArea() {
  final style = web.window.getComputedStyle(_element());
  return EdgeInsets.fromLTRB(
    _px(style.paddingLeft),
    _px(style.paddingTop),
    _px(style.paddingRight),
    _px(style.paddingBottom),
  );
}

/// Calls [onChange] when the insets may have changed (rotation, resize);
/// returns a function that stops it.
void Function() listenWebSafeArea(void Function() onChange) {
  final listener = ((web.Event _) => onChange()).toJS;
  web.window.addEventListener('resize', listener);
  web.window.addEventListener('orientationchange', listener);
  return () {
    web.window.removeEventListener('resize', listener);
    web.window.removeEventListener('orientationchange', listener);
  };
}
