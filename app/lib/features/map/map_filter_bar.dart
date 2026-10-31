import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
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
        ref,
        keyPrefix: 'mapTag-',
        selected: tags,
        onToggle: ctrl.toggleTag,
        onClear: ctrl.clearTags,
        withDivider: false,
        clearKey: const Key('mapTagsClear'),
      ),
    ];
    return SizedBox(
      height: 52,
      child: GlassSurface(
        radius: 26,
        // One lens over the scrolling chips, not one per chip: glass reads
        // the backdrop, so it belongs above a list rather than inside it.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final w in items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(child: w),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
