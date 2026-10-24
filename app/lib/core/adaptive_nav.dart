import 'package:flutter/material.dart';

import 'responsive.dart';

class NavItem {
  const NavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Bottom navigation bar on narrow windows (phone portrait); a side rail
/// otherwise (phone landscape, tablet, desktop), extended with labels on wide
/// windows.
class AdaptiveNavScaffold extends StatelessWidget {
  const AdaptiveNavScaffold({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    if (!context.useNavRail) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: [
            for (final i in items)
              NavigationDestination(icon: Icon(i.icon), label: i.label),
          ],
        ),
      );
    }
    final extended = context.extendedRail;
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          children: [
            // Scrolls instead of overflowing on very short landscape phones.
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onSelected,
                      extended: extended,
                      labelType: extended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.selected,
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
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
