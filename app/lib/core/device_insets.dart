import 'package:flutter/widgets.dart';

import 'web_safe_area.dart';

/// The parts of the screen that system UI covers (status bar, notch, home
/// indicator), for this device. On the web Flutter reports none, so in an
/// installed web app on iOS (standalone, drawn edge to edge) content and
/// buttons ended up under the clock and in the home indicator's swipe zone,
/// where iOS swallows taps. There they come from CSS
/// `env(safe-area-inset-*)` instead.
///
/// [DeviceInsets] at the app's root adds them to the [MediaQuery] below it;
/// [DeviceInsets.of] gives them where a widget must not take the
/// [MediaQuery] padding (a Scaffold removes that from its body).
class DeviceInsets extends StatefulWidget {
  const DeviceInsets({super.key, required this.child, this.debugInsets});

  final Widget child;

  /// Replaces the browser's insets (tests).
  final EdgeInsets? debugInsets;

  /// This device's insets: what [DeviceInsets] found, else the view's.
  static EdgeInsets of(BuildContext context) {
    final view = MediaQueryData.fromView(View.of(context)).viewPadding;
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DeviceInsetsScope>();
    return scope == null ? view : _max(view, scope.insets);
  }

  static EdgeInsets _max(EdgeInsets a, EdgeInsets b) => EdgeInsets.fromLTRB(
    a.left > b.left ? a.left : b.left,
    a.top > b.top ? a.top : b.top,
    a.right > b.right ? a.right : b.right,
    a.bottom > b.bottom ? a.bottom : b.bottom,
  );

  @override
  State<DeviceInsets> createState() => _DeviceInsetsState();
}

class _DeviceInsetsState extends State<DeviceInsets> {
  EdgeInsets _web = EdgeInsets.zero;
  void Function()? _unlisten;

  @override
  void initState() {
    super.initState();
    _web = readWebSafeArea();
    _unlisten = listenWebSafeArea(() {
      final now = readWebSafeArea();
      if (mounted && now != _web) setState(() => _web = now);
    });
  }

  @override
  void dispose() {
    _unlisten?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extra = widget.debugInsets ?? _web;
    final data = MediaQuery.of(context);
    final insets = DeviceInsets._max(data.viewPadding, extra);
    return _DeviceInsetsScope(
      insets: insets,
      child: MediaQuery(
        data: data.copyWith(
          viewPadding: insets,
          padding: DeviceInsets._max(data.padding, extra),
        ),
        child: widget.child,
      ),
    );
  }
}

class _DeviceInsetsScope extends InheritedWidget {
  const _DeviceInsetsScope({required this.insets, required super.child});

  final EdgeInsets insets;

  @override
  bool updateShouldNotify(_DeviceInsetsScope old) => insets != old.insets;
}
