import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Height of the floating glass tab bar and the gap kept below it. The shell
/// adds both to the bottom padding it hands to its pages.
const double kGlassTabBarHeight = 64;
const double kGlassTabBarGap = 12;

/// Height of [GlassAppBar]'s capsule, without the status bar and margins.
const double kGlassAppBarHeight = 56;

/// `extra` of a spot route opened by pulling up its sheet: the sheet already
/// looks like the page, so the page appears without a transition.
const Object kSpotFromSheet = 'spotFromSheet';

/// Text and icons on glass. The tint keeps them readable over any backdrop,
/// from the dark map to a bright satellite image or photo.
const Color kOnGlass = Color(0xF2FFFFFF);
const Color _glassTint = Color(0x66101410);

/// What glass turns into when transparency is off.
const Color kSolidGlass = Color(0xFF232823);
const Color _solidRim = Color(0x1FFFFFFF);

/// Replaces all glass below it with solid surfaces of the same size: no lens,
/// so no backdrop read, blur or refraction. Without this widget above them
/// surfaces are glass; they do not depend on a ProviderScope for that.
class SolidGlass extends InheritedWidget {
  const SolidGlass({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SolidGlass>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(SolidGlass oldWidget) => enabled != oldWidget.enabled;
}

/// The colour of a [GlassPanel] here; opaque when glass is off.
Color glassTint(BuildContext context) =>
    SolidGlass.of(context) ? kSolidGlass : _glassTint;

/// The app's one glass look, so bars, buttons and sheets match.
LiquidGlassStyle glassStyle({double radius = 28}) => LiquidGlassStyle(
  shape: LiquidGlassShape.continuousRoundedRectangle(cornerRadius: radius),
  specular: const LiquidGlassLight.specular(),
  color: _glassTint,
  blur: 7,
  refractionIndex: 1.08,
  refractionWidth: 16,
);

/// Call once before [runApp]: Skia and the web have no live backdrop to
/// refract, so they get the frosted variant; pre-compiling the shaders
/// avoids an empty first frame of glass on Impeller.
Future<void> initGlass() async {
  LiquidGlassEngine.liteGlassOnSkia = true;
  await LiquidGlassShaders.ensureLoaded();
}

/// The bare surface every piece of glass stands on: a lens, or under
/// [SolidGlass] a filled shape. Either way it clips [child]. Glass takes no
/// pointer events of its own; a solid surface stops those on its empty parts.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 28,
    this.color,
  });

  final Widget child;
  final double radius;

  /// Replaces [glassTint]; derive it from that one to stay opaque when solid.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!SolidGlass.of(context)) {
      final style = glassStyle(radius: radius);
      return LiquidGlassLens(
        style: color == null ? style : style.copyWith(color: color),
        child: child,
      );
    }
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: const BorderSide(color: _solidRim),
    );
    // Opaque, so a tap on an empty part must not reach what it hides.
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: CustomPaint(
        painter: _SolidPainter(shape, color ?? kSolidGlass),
        child: ClipPath.shape(shape: shape, child: child),
      ),
    );
  }
}

class _SolidPainter extends CustomPainter {
  const _SolidPainter(this.shape, this.color);

  final ShapeBorder shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawPath(shape.getOuterPath(rect), Paint()..color = color);
    shape.paint(canvas, rect);
  }

  // Like a lens: taps on an empty surface go to whatever is below it.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_SolidPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
}

/// A floating panel of glass. Light-on-glass colours apply to its [child].
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassPanel(
      radius: radius,
      child: Theme(
        data: theme.copyWith(
          iconTheme: theme.iconTheme.copyWith(color: kOnGlass),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: kOnGlass),
          ),
          chipTheme: theme.chipTheme.copyWith(
            backgroundColor: const Color(0x24FFFFFF),
            iconTheme: const IconThemeData(size: 18, color: kOnGlass),
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: kOnGlass),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling row of chips on glass. Chips stop short of the
/// glass edge and fade out before they reach it, so nothing runs over the
/// rim while scrolling.
class GlassChipRow extends StatelessWidget {
  const GlassChipRow({super.key, required this.children});

  final List<Widget> children;

  static const double _inset = 8;
  static const double _fade = 12;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _inset),
    child: LayoutBuilder(
      builder: (context, c) {
        final stop = _fade / c.maxWidth;
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: const [
              Color(0x00000000),
              Color(0xFF000000),
              Color(0xFF000000),
              Color(0x00000000),
            ],
            stops: [0, stop, 1 - stop, 1],
          ).createShader(bounds),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: _fade),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Center(child: children[i]),
          ),
        );
      },
    ),
  );
}

/// App bar as a capsule of glass floating over the page. Use it with
/// `Scaffold(extendBodyBehindAppBar: true)`, and start scrolling content at
/// [GlassAppBar.contentTop] so it can pass underneath.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final Widget title;
  final Widget? leading;
  final List<Widget> actions;

  static const double _margin = 8;

  /// Where a page's content starts below the bar.
  static double contentTop(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + kGlassAppBarHeight + 2 * _margin;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kGlassAppBarHeight + 2 * _margin);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.titleLarge
        ?.copyWith(color: kOnGlass);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(_margin),
        child: SizedBox(
          height: kGlassAppBarHeight,
          child: GlassSurface(
            child: Row(
              children: [
                if (leading != null) leading! else const SizedBox(width: 20),
                Expanded(
                  child: DefaultTextStyle(
                    style: text ?? const TextStyle(color: kOnGlass),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: title,
                  ),
                ),
                ...actions,
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _tabPadding = 6.0;
const _tabItemStyle = LiquidGlassTabItemStyle(
  selectedColor: kOnGlass,
  unselectedColor: Color(0xB3FFFFFF),
);
const _tabPillColor = Color(0x2EAEAEB2);
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
  final List<LiquidGlassTabBarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!SolidGlass.of(context)) {
      return LiquidGlassTabBar(
        width: width,
        height: kGlassTabBarHeight,
        // on top of the safe area, which the bar adds itself
        margin: const EdgeInsets.only(bottom: kGlassTabBarGap),
        selectedIndex: selectedIndex,
        onChanged: onChanged,
        style: glassStyle(radius: kGlassTabBarHeight / 2),
        pillStyle: const LiquidGlassTabPillStyle(
          mode: LiquidGlassPillMode.impellerOnly,
        ),
        itemStyle: _tabItemStyle,
        items: items,
      );
    }
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
              child: GlassPanel(
                radius: kGlassTabBarHeight / 2,
                child: _SolidTabs(
                  cellWidth: (width - 2 * _tabPadding) / items.length,
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
  final List<LiquidGlassTabBarItem> items;
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
    final color = _tabItemStyle.colorFor(selected: isSelected);
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
                Icon(
                  item.icon,
                  color: color,
                  size: _tabItemStyle.iconSizeFor(underGlass: 0),
                ),
                SizedBox(height: _tabItemStyle.iconLabelGap),
                Text(
                  item.label!,
                  style: TextStyle(
                    color: color,
                    fontSize: _tabItemStyle.labelFontSizeFor(underGlass: 0),
                    fontWeight: _tabItemStyle.fontWeightFor(
                      selected: isSelected,
                    ),
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
      padding: const EdgeInsets.all(_tabPadding),
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

const _fabHeight = 48.0;

/// Extended floating action button.
class GlassFab extends StatelessWidget {
  const GlassFab({
    super.key,
    required this.radius,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final double radius;
  final IconData icon;
  final Widget label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (!SolidGlass.of(context)) {
      return LiquidGlassFab.extended(
        style: glassStyle(radius: radius),
        foregroundColor: kOnGlass,
        onPressed: onPressed,
        icon: icon,
        label: label,
      );
    }
    final corners = BorderRadius.circular(radius);
    return SizedBox(
      height: _fabHeight,
      child: GlassPanel(
        radius: radius,
        child: Material(
          color: Colors.transparent,
          borderRadius: corners,
          child: InkWell(
            borderRadius: corners,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: kOnGlass, size: 20),
                    const SizedBox(width: 8),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        color: kOnGlass,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                      child: label,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal sheet floating above the bottom edge, on glass.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required double radius,
  bool useRootNavigator = false,
  bool isScrollControlled = false,
  BoxConstraints? constraints,
}) {
  if (!SolidGlass.of(context)) {
    return showLiquidGlassSheet<T>(
      context: context,
      style: glassStyle(radius: radius),
      foregroundColor: kOnGlass,
      padding: EdgeInsets.zero,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      constraints: constraints,
      builder: builder,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    clipBehavior: Clip.none,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    constraints: constraints,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _SolidSheet(radius: radius, child: builder(context)),
    ),
  );
}

/// What [LiquidGlassSheet] lays out, on a solid surface.
class _SolidSheet extends StatelessWidget {
  const _SolidSheet({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: LiquidGlassSheet.defaultMargin(
      LiquidGlassSheetAnchor.floating,
      bottomInset: MediaQuery.viewPaddingOf(context).bottom,
    ),
    child: GlassPanel(
      radius: radius,
      child: Material(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: kOnGlass.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
              ),
              if (constraints.hasBoundedHeight)
                Flexible(child: child)
              else
                child,
            ],
          ),
        ),
      ),
    ),
  );
}
