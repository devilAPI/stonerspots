import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:glisse/glisse.dart' as g;

import 'glass.dart';

// The floating tab bar: Glisse's glass tab bar, or solid tabs that answer
// the same way.

/// One tab of a [GlassTabBar].
class BottomBarTab {
  const BottomBarTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Width of one tab, as Glisse's tab bar with icons lays them out, and the
/// bar's inset around them. Solid tabs use the same, so they sit where the
/// glass ones do.
const double kGlassTabWidth = 72;
const double _tabInset = 4;
const _tabPadding = EdgeInsets.all(_tabInset);
const _tabUnselected = Color(0xB3FFFFFF);
const _tabIconSize = 26.0;
const _tabLabelSize = 10.0;
const _tabLabelGap = 3.0;
const _tabPillColor = Color(0x2EAEAEB2);
const _tabSlide = Duration(milliseconds: 320);

/// A round button beside the tabs, like iOS 27's search button.
class GlassBarAction {
  const GlassBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.key,
  });

  final IconData icon;

  /// Tooltip and screen-reader label.
  final String label;
  final VoidCallback onPressed;
  final Key? key;
}

/// Gap between the tabs and the [GlassBarAction].
const double kGlassBarActionGap = 8;

/// Width of a [GlassTabBar] with [tabs] tabs and maybe an action.
double glassTabBarWidth(int tabs, {bool action = false}) =>
    tabs * kGlassTabWidth +
    2 * _tabInset +
    (action ? kGlassTabBarHeight + kGlassBarActionGap : 0);

/// The floating tab bar, with an optional round [action] to its right. It
/// places itself at the bottom of the [Stack] it is the last child of,
/// above the safe area, as wide as its tabs ([glassTabBarWidth]).
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    this.action,
  });

  final List<BottomBarTab> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final GlassBarAction? action;

  @override
  Widget build(BuildContext context) {
    final glass = !SolidGlass.of(context);
    final action = this.action;
    final Widget tabs = glass
        ? _SelectOnCancel(
            tabs: items.length,
            onChanged: onChanged,
            child: g.GlassTabBar<int>(
              items: [
                for (var i = 0; i < items.length; i++)
                  g.GlassSegment(
                    value: i,
                    label: items[i].label,
                    icon: items[i].icon,
                  ),
              ],
              value: selectedIndex,
              onChanged: onChanged,
            ),
          )
        : SizedBox(
            width: glassTabBarWidth(items.length),
            child: GlassPanel(
              radius: kGlassTabBarHeight / 2,
              child: _SolidTabs(
                cellWidth: kGlassTabWidth,
                items: items,
                selectedIndex: selectedIndex,
                onChanged: onChanged,
              ),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + kGlassTabBarGap,
          child: Align(
            child: SizedBox(
              height: kGlassTabBarHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tabs,
                  if (action != null) ...[
                    const SizedBox(width: kGlassBarActionGap),
                    glass
                        ? _GlassActionButton(action: action)
                        : _SolidActionButton(action: action),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Selects the tab under a press the system cancels. iOS cancels touches
/// near the bottom edge of a home-screen web app, where the bar is, and
/// Glisse's bar takes a cancelled press for none.
class _SelectOnCancel extends StatefulWidget {
  const _SelectOnCancel({
    required this.tabs,
    required this.onChanged,
    required this.child,
  });

  final int tabs;
  final ValueChanged<int> onChanged;
  final Widget child;

  @override
  State<_SelectOnCancel> createState() => _SelectOnCancelState();
}

class _SelectOnCancelState extends State<_SelectOnCancel> {
  int? _pointer;
  Offset _at = Offset.zero;

  void _track(PointerEvent e) {
    if (e.pointer == _pointer) _at = e.localPosition;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (e) {
      _pointer = e.pointer;
      _at = e.localPosition;
    },
    onPointerMove: _track,
    onPointerUp: (e) {
      if (e.pointer == _pointer) _pointer = null;
    },
    onPointerCancel: (e) {
      if (e.pointer != _pointer) return;
      _pointer = null;
      widget.onChanged(
        ((_at.dx - _tabInset) / kGlassTabWidth).floor().clamp(
          0,
          widget.tabs - 1,
        ),
      );
    },
    child: widget.child,
  );
}

/// The round glass [GlassBarAction]: Glisse's icon button, which swells and
/// stretches under the finger.
class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({required this.action});

  final GlassBarAction action;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: action.label,
    excludeFromSemantics: true,
    child: g.GlassButton(
      key: action.key,
      height: kGlassTabBarHeight,
      semanticLabel: action.label,
      onPressed: action.onPressed,
      icon: Icon(action.icon, color: kOnGlass, size: 28),
    ),
  );
}

/// [_GlassActionButton] on a solid surface.
class _SolidActionButton extends StatelessWidget {
  const _SolidActionButton({required this.action});

  final GlassBarAction action;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: kGlassTabBarHeight,
    child: GlassPanel(
      radius: kGlassTabBarHeight / 2,
      child: Material(
        type: MaterialType.transparency,
        child: IconButton(
          key: action.key,
          tooltip: action.label,
          onPressed: action.onPressed,
          icon: Icon(action.icon, color: kOnGlass, size: 28),
        ),
      ),
    ),
  );
}

/// The tabs of a solid [GlassTabBar]. They answer like the glass ones: a tap
/// selects, and press and hold drags the selection along the bar.
class _SolidTabs extends StatefulWidget {
  const _SolidTabs({
    required this.cellWidth,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  final double cellWidth;
  final List<BottomBarTab> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  State<_SolidTabs> createState() => _SolidTabsState();
}

class _SolidTabsState extends State<_SolidTabs> {
  /// Under the finger while dragging, in tabs; null otherwise.
  double? _held;

  int get _last => widget.items.length - 1;

  double _tabAt(Offset local) =>
      (local.dx / widget.cellWidth - 0.5).clamp(0.0, _last.toDouble());

  void _release() {
    final held = _held;
    if (held == null) return;
    setState(() => _held = null);
    if (held.round() != widget.selectedIndex) widget.onChanged(held.round());
  }

  Widget _tab(int i, int selected) {
    final item = widget.items[i];
    final isSelected = i == selected;
    final color = isSelected ? kOnGlass : _tabUnselected;
    return Expanded(
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: isSelected,
          onTap: () => widget.onChanged(i),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.icon, color: color, size: _tabIconSize),
                const SizedBox(height: _tabLabelGap),
                Text(
                  item.label,
                  style: TextStyle(
                    color: color,
                    fontSize: _tabLabelSize,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final held = _held;
    final selected = held?.round() ?? widget.selectedIndex;
    return Padding(
      padding: _tabPadding,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTapUp = (d) => widget.onChanged(
                  (d.localPosition.dx / widget.cellWidth).floor().clamp(
                    0,
                    _last,
                  ),
                ),
              ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 100),
                ),
                (r) => r
                  ..onLongPressStart = ((d) =>
                      setState(() => _held = _tabAt(d.localPosition)))
                  ..onLongPressMoveUpdate = ((d) =>
                      setState(() => _held = _tabAt(d.localPosition)))
                  ..onLongPressEnd = ((_) => _release())
                  ..onLongPressCancel = _release,
              ),
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedPositioned(
              key: const Key('solidTabPill'),
              duration: held == null ? _tabSlide : kThemeChangeDuration,
              curve: Curves.easeOutCubic,
              left: (held ?? widget.selectedIndex) * widget.cellWidth,
              top: 0,
              bottom: 0,
              width: widget.cellWidth,
              child: const DecoratedBox(
                decoration: ShapeDecoration(
                  color: _tabPillColor,
                  shape: StadiumBorder(),
                ),
              ),
            ),
            Row(children: [for (var i = 0; i <= _last; i++) _tab(i, selected)]),
          ],
        ),
      ),
    );
  }
}
