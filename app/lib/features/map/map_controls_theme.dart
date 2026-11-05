import 'package:flutter/material.dart';

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
