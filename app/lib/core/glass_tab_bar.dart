import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass.dart';

// The floating tab bar: glass with the loupe, or solid tabs that answer
// the same way.

/// The tab row's inset, as in [LoupeTabBar], so solid tabs sit where the
/// glass ones do.
const _tabPadding = EdgeInsets.symmetric(horizontal: 9, vertical: 4);
const _tabUnselected = Color(0xB3FFFFFF);
const _tabIconSize = 24.0;
const _tabLabelSize = 10.0;
const _tabLabelGap = 3.0;
const _tabPillColor = Color(0x2EAEAEB2);

/// Blend distance of the tab bar's glass: below the gap to anything beside
/// it, so it only merges with what is pulled close.
const _tabBlend = 5.0;
const _tabShadows = [
  BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8)),
];
const _tabSlide = Duration(milliseconds: 320);

/// The floating tab bar. It places itself at the bottom of the [Stack] it is
/// the last child of, above the safe area.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.width,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  final double width;
  final List<BottomBarTab> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final glass = !SolidGlass.of(context);
    final fake = SolidGlass.fakeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.paddingOf(context).bottom + kGlassTabBarGap,
          child: Align(
            child: SizedBox(
              width: width,
              height: kGlassTabBarHeight,
              child: glass
                  ? LiquidGlassLayer(
                      settings: kGlassSettings,
                      fake: fake,
                      defaultAppearance: glassAppearance(),
                      child: LiquidGlassBlendGroup(
                        blend: _tabBlend,
                        child: LoupeTabBar(
                          tabs: items,
                          selectedIndex: selectedIndex,
                          onSelected: onChanged,
                          height: kGlassTabBarHeight,
                          shadows: _tabShadows,
                          fake: fake,
                          labelColor: kOnGlass,
                          tint: Theme.of(context).colorScheme.primary,
                          tintBrightness: Brightness.dark,
                        ),
                      ),
                    )
                  : GlassPanel(
                      radius: kGlassTabBarHeight / 2,
                      child: _SolidTabs(
                        cellWidth:
                            (width - _tabPadding.horizontal) / items.length,
                        items: items,
                        selectedIndex: selectedIndex,
                        onChanged: onChanged,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
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
