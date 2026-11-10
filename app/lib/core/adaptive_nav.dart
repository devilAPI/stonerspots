import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'glass.dart';
import 'responsive.dart';

class NavItem {
  const NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

const double _railMargin = 12;
const double _railWidth = 80;
const double _extendedRailWidth = 200;

/// Glass navigation floating over the page: a bottom tab bar on narrow
/// windows (phone portrait); a side rail otherwise (phone landscape, tablet,
/// desktop), extended with labels on wide windows.
///
/// [body] runs edge to edge beneath it; the space the navigation covers is
/// added to the body's [MediaQuery] padding.
class AdaptiveNavScaffold extends StatelessWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.action,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  /// A round button beside the bottom tabs (search); only with the tabs,
  /// the rail's pages offer it themselves.
  final GlassBarAction? action;

  /// [body] with [inset] added to its padding.
  Widget _bodyBeneath(BuildContext context, EdgeInsets inset) {
    final media = MediaQuery.of(context);
    return Positioned.fill(
      child: MediaQuery(
        data: media.copyWith(padding: media.padding + inset),
        child: body,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    if (!context.useNavRail) {
      final width = MediaQuery.sizeOf(context).width;
      return Scaffold(
        body: Stack(
          children: [
            _bodyBeneath(
              context,
              const EdgeInsets.only(
                bottom: kGlassTabBarHeight + kGlassTabBarGap,
              ),
            ),
            GlassTabBar(
              width: math.min(
                width - 32,
                360 +
                    (action == null
                        ? 0
                        : kGlassTabBarHeight + kGlassBarActionGap),
              ),
              action: action,
              selectedIndex: selectedIndex,
              onChanged: onSelected,
              items: [
                for (final i in items)
                  BottomBarTab(icon: i.icon, label: i.label),
              ],
            ),
          ],
        ),
      );
    }
    final extended = context.extendedRail;
    final railWidth = extended ? _extendedRailWidth : _railWidth;
    return Scaffold(
      body: Stack(
        children: [
          _bodyBeneath(
            context,
            EdgeInsets.only(left: railWidth + 2 * _railMargin),
          ),
          Positioned(
            top: safe.top + _railMargin,
            bottom: safe.bottom + _railMargin,
            left: safe.left + _railMargin,
            width: railWidth,
            child: Align(
              alignment: Alignment.topCenter,
              // Scrolls instead of overflowing on very short landscape phones.
              child: SingleChildScrollView(
                child: GlassSurface(
                  radius: 28,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    removeRight: true,
                    removeTop: true,
                    removeBottom: true,
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onSelected,
                        extended: extended,
                        minExtendedWidth: _extendedRailWidth,
                        labelType: extended
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.selected,
                        unselectedIconTheme: const IconThemeData(
                          color: kOnGlass,
                        ),
                        unselectedLabelTextStyle: const TextStyle(
                          color: kOnGlass,
                        ),
                        selectedLabelTextStyle: const TextStyle(
                          color: kOnGlass,
                        ),
                        destinations: [
                          for (final i in items)
                            NavigationRailDestination(
                              icon: Icon(i.icon),
                              label: Text(i.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
