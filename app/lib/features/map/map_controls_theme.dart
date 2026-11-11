import 'package:flutter/material.dart';

import '../../core/glass.dart';

/// Icon size of the map's control buttons.
const double kMapControlIconSize = 22;

/// One look for the map's control column: every button the same size, the
/// same icon size and colour, so the outlined icons line up evenly.
class MapControlsTheme extends StatelessWidget {
  const MapControlsTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(
          fixedSize: const Size.square(44),
          padding: EdgeInsets.zero,
          iconSize: kMapControlIconSize,
          foregroundColor: scheme.onSurface,
          tapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
        ),
      ),
      child: child,
    );
  }
}

/// Width of [MapControlColumn].
const double kMapControlColumnWidth = 52;

/// The map's control buttons, stacked on one glass capsule.
class MapControlColumn extends StatelessWidget {
  const MapControlColumn({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: kMapControlColumnWidth,
    child: GlassSurface(
      radius: kMapControlColumnWidth / 2,
      child: MapControlsTheme(
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}
