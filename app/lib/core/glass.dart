import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Height of the floating glass tab bar and the gap kept below it. The shell
/// adds both to the bottom padding it hands to its pages.
const double kGlassTabBarHeight = 64;
const double kGlassTabBarGap = 12;

/// Height of [GlassAppBar]'s capsule, without the status bar and margins.
const double kGlassAppBarHeight = 56;

/// Text and icons on glass. The tint keeps them readable over any backdrop,
/// from the dark map to a bright satellite image or photo.
const Color kOnGlass = Color(0xF2FFFFFF);
const Color _glassTint = Color(0x66101410);

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

/// A floating panel of glass. Light-on-glass colours apply to its [child].
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiquidGlassLens(
      style: glassStyle(radius: radius),
      child: Theme(
        data: theme.copyWith(
          iconTheme: theme.iconTheme.copyWith(color: kOnGlass),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(foregroundColor: kOnGlass),
          ),
          chipTheme: theme.chipTheme.copyWith(
            backgroundColor: const Color(0x14FFFFFF),
            selectedColor: theme.colorScheme.primary.withValues(alpha: 0.45),
            side: BorderSide.none,
            labelStyle: const TextStyle(color: kOnGlass),
            iconTheme: const IconThemeData(color: kOnGlass),
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
