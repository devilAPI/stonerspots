import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/spot_tag_widgets.dart';
import 'spots_controller.dart';

/// Horizontally scrolling filter row over the map: the multi-select tag
/// toggles.
class MapFilterBar extends ConsumerWidget {
  const MapFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(spotsControllerProvider.select((s) => s.tags));
    final ctrl = ref.read(spotsControllerProvider.notifier);
    final items = <Widget>[
      ...spotTagFilterItems(
        context,
        keyPrefix: 'mapTag-',
        selected: tags,
        onToggle: ctrl.toggleTag,
        onClear: ctrl.clearTags,
        withDivider: false,
        clearKey: const Key('mapTagsClear'),
      ),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final w in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: w),
            ),
        ],
      ),
    );
  }
}
