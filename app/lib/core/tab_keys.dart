import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard switching between [count] tabs while this page is on top:
/// 1 … [count] pick a tab, Ctrl+Tab / Ctrl+Shift+Tab go to the next /
/// previous one. Browsers keep Ctrl+Tab (and Alt/Ctrl+digit) for their own
/// tabs, so on the web the plain digits are the ones that work. Keys are
/// left alone while a text field has focus (digits are typed, not taken)
/// and while another page or a dialog is above this one.
class TabKeys extends StatefulWidget {
  const TabKeys({
    super.key,
    required this.count,
    required this.index,
    required this.onSelect,
    required this.child,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget child;

  @override
  State<TabKeys> createState() => _TabKeysState();
}

class _TabKeysState extends State<TabKeys> {
  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  void initState() {
    super.initState();
    // Global, not a Shortcuts widget: on a fresh page nothing has focus
    // yet, and Shortcuts only see keys of the focused subtree.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  static bool _typing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? true) || _typing()) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    final w = widget;
    int? to;
    if (event.logicalKey == LogicalKeyboardKey.tab && keys.isControlPressed) {
      to = (w.index + (keys.isShiftPressed ? -1 : 1)) % w.count;
    } else if (!keys.isControlPressed &&
        !keys.isAltPressed &&
        !keys.isMetaPressed) {
      final i = _digits.indexOf(event.logicalKey);
      if (i >= 0 && i < w.count) to = i;
    }
    if (to == null) return false;
    if (to != w.index) w.onSelect(to);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
