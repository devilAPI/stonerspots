import 'package:flutter/material.dart';

/// Width breakpoints (logical px). Phones in landscape and tablets share the
/// "rail + two panes" layout; the bottom bar is for narrow windows only.
const double kRailBreakpoint = 600;
const double kTwoPaneBreakpoint = 720;
const double kExtendedRailBreakpoint = 1000;

/// Readable width for single-column content (feed, forms, lists).
const double kContentMaxWidth = 680;

/// Feed grid on tablets/desktops: columns of at least this width ...
const double kFeedTileMinWidth = 300;

/// ... up to this many, inside at most [kFeedGridMaxWidth].
const int kFeedMaxColumns = 4;
const double kFeedGridMaxWidth = 1400;

/// Shortest window side below which the device counts as a phone (in either
/// orientation).
const double kPhoneShortestSide = 600;

/// Number of feed columns for a pane of [width] (1 = plain list).
int feedColumns(double width) {
  final usable = (width < kFeedGridMaxWidth ? width : kFeedGridMaxWidth) - 24;
  return (usable / kFeedTileMinWidth).floor().clamp(1, kFeedMaxColumns);
}

extension ResponsiveContext on BuildContext {
  double get _width => MediaQuery.sizeOf(this).width;

  /// Side navigation rail instead of a bottom bar.
  bool get useNavRail => _width >= kRailBreakpoint;

  /// Rail with text labels next to the icons.
  bool get extendedRail => _width >= kExtendedRailBreakpoint;

  /// Room for a side-by-side layout (e.g. gallery | details).
  bool get twoPane => _width >= kTwoPaneBreakpoint;

  /// Phone-sized window (portrait or landscape).
  bool get isPhone => MediaQuery.sizeOf(this).shortestSide < kPhoneShortestSide;

  /// Phone held sideways: little height, so content goes side by side.
  bool get isPhoneLandscape {
    final size = MediaQuery.sizeOf(this);
    return isPhone && size.width > size.height;
  }
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
