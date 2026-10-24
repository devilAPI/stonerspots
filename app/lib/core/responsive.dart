import 'package:flutter/material.dart';

/// Width breakpoints (logical px). Phones in landscape and tablets share the
/// "rail + two panes" layout; the bottom bar is for narrow windows only.
const double kRailBreakpoint = 600;
const double kTwoPaneBreakpoint = 720;
const double kExtendedRailBreakpoint = 1000;

/// Readable width for single-column content (feed, forms, lists).
const double kContentMaxWidth = 680;

extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  /// Side navigation rail instead of a bottom bar.
  bool get useNavRail => _width >= kRailBreakpoint;

  /// Rail with text labels next to the icons.
  bool get extendedRail => _width >= kExtendedRailBreakpoint;

  /// Room for a side-by-side layout (e.g. gallery | details).
  bool get twoPane => _width >= kTwoPaneBreakpoint;
}

/// Horizontal padding that centres a column of at most [maxWidth] in a scroll
/// view of [width]: use it as list padding when the scroll area itself must
/// stay full-width (mouse wheel / scrollbar at the window edge).
double sideGutter(double width, {double maxWidth = kContentMaxWidth}) =>
    width > maxWidth ? (width - maxWidth) / 2 : 0;

/// Centres [child] and keeps it at most [maxWidth] wide, so lists and forms
/// do not stretch across a desktop window.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = kContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
