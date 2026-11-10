import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'device_insets.dart';
import 'flutter_gpu_check.dart';

export 'glass_sheet.dart';
export 'glass_tab_bar.dart';
export 'loupe_tab_bar/loupe_tab_bar.dart' show BottomBarTab, LoupeTabBar;

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
  const SolidGlass({
    super.key,
    required this.enabled,
    this.realGlass = true,
    required super.child,
  });

  final bool enabled;

  /// Glass may refract where the device can ([realGlassAvailable]); off,
  /// it is always the frosted kind.
  final bool realGlass;

  static SolidGlass? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SolidGlass>();

  static bool of(BuildContext context) => _of(context)?.enabled ?? false;

  /// Whether glass here is drawn frosted (FakeGlass) instead of refracting.
  static bool fakeOf(BuildContext context) =>
      !realGlassAvailable || !(_of(context)?.realGlass ?? true);

  @override
  bool updateShouldNotify(SolidGlass oldWidget) =>
      enabled != oldWidget.enabled || realGlass != oldWidget.realGlass;
}

/// The colour of a [GlassPanel] here; opaque when glass is off.
Color glassTint(BuildContext context) =>
    SolidGlass.of(context) ? kSolidGlass : _glassTint;

/// The app's one glass look, so bars, buttons and sheets match.
const kGlassSettings = LiquidGlassSettings();

/// Whether this device draws real, refracting glass: Impeller with Flutter
/// GPU (switched on in the Android and iOS app config). Elsewhere (the web,
/// Skia, a GPU without support) glass is frosted, the package's FakeGlass.
/// Known after [initGlass].
bool get realGlassAvailable => _realGlassAvailable;
bool _realGlassAvailable = false;

@visibleForTesting
set debugRealGlassAvailable(bool value) => _realGlassAvailable = value;

/// The tint of glass here, [color] or [glassTint]'s.
LiquidGlassAppearance glassAppearance([Color color = _glassTint]) =>
    LiquidGlassAppearance(tint: color);

/// Call once before [runApp]: loads the glass shaders, so the first glass
/// on screen is not drawn without them for a frame or two, and finds out
/// whether real glass works here ([realGlassAvailable]).
Future<void> initGlass() async {
  await LiquidGlass.precache();
  if (kIsWeb || !ui.ImageFilter.isShaderFilterSupported) return;
  // without Flutter GPU the glass layers fall back to frosted glass by
  // themselves, and the app must know (the tab bar's loupe is stacked
  // differently then)
  _realGlassAvailable = flutterGpuAvailable();
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
      return LiquidGlass.withOwnLayer(
        settings: kGlassSettings,
        fake: SolidGlass.fakeOf(context),
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        appearance: glassAppearance(color ?? _glassTint),
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
      // From the view: a Scaffold takes the top padding out of its body's
      // MediaQuery, and this is called from inside bodies as well.
      DeviceInsets.of(context).top + kGlassAppBarHeight + 2 * _margin;

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
    final corners = BorderRadius.circular(radius);
    final button = SizedBox(
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
    if (SolidGlass.of(context)) return button;
    // swells and stretches under the finger, like the tab bar
    return LiquidStretch(interactionScale: 1.05, child: button);
  }
}

/// A dialog on glass, laid out like an [AlertDialog]: [title], [content]
/// and the [actions] in a row at the end. Show it with `showDialog`.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
  });

  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GlassSurface(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DefaultTextStyle.merge(
                  style: text.titleLarge?.copyWith(color: kOnGlass),
                  child: title,
                ),
                const SizedBox(height: 14),
                Flexible(child: SingleChildScrollView(child: content)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 8,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
