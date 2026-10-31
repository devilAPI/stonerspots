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
