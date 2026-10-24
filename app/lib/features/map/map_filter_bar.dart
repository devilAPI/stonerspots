import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'spots_controller.dart';

const _categories = [
  'bench',
  'river',
  'lake',
  'viewpoint',
  'forest',
  'park',
  'other',
];

String _categoryLabel(AppLocalizations l, String? c) => switch (c) {
  'bench' => l.categoryBench,
  'river' => l.categoryRiver,
  'lake' => l.categoryLake,
  'viewpoint' => l.categoryViewpoint,
  'forest' => l.categoryForest,
  'park' => l.categoryPark,
  'other' => l.categoryOther,
  _ => l.categoryAll,
};

/// Horizontally scrolling filter row over the map: category choice, a
/// divider, then the multi-select tag toggles.
class MapFilterBar extends ConsumerWidget {
  const MapFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final category = ref.watch(
      spotsControllerProvider.select((s) => s.category),
    );
    final tags = ref.watch(spotsControllerProvider.select((s) => s.tags));
    final ctrl = ref.read(spotsControllerProvider.notifier);
    final items = <Widget>[
      for (final c in <String?>[null, ..._categories])
        ChoiceChip(
          label: Text(_categoryLabel(l10n, c)),
          selected: category == c,
          onSelected: (_) => ctrl.setCategory(c),
        ),
      ...spotTagFilterItems(
        context,
        keyPrefix: 'mapTag-',
        selected: tags,
        onToggle: ctrl.toggleTag,
        onClear: ctrl.clearTags,
        dividerKey: const Key('mapTagDivider'),
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
