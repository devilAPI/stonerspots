import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import 'models.dart';
import 'tag_catalog.dart';

/// Icons a tag can have, by the name stored in the catalog. Admins pick from
/// these; unknown names show [kFallbackTagIcon].
const Map<String, IconData> kTagIcons = {
  'roof': Icons.roofing,
  'seating': Icons.chair_alt,
  'view': Icons.landscape,
  'quiet': Icons.volume_off,
  'shade': Icons.wb_shade,
  'water': Icons.water_drop,
  'lit': Icons.lightbulb_outline,
  'fire': Icons.local_fire_department,
  'tree': Icons.park,
  'forest': Icons.forest,
  'grass': Icons.grass,
  'mountain': Icons.terrain,
  'sun': Icons.wb_sunny_outlined,
  'night': Icons.nightlight_outlined,
  'beach': Icons.beach_access,
  'table': Icons.table_restaurant,
  'trash': Icons.delete_outline,
  'toilet': Icons.wc,
  'parking': Icons.local_parking,
  'bike': Icons.pedal_bike,
  'car': Icons.directions_car,
  'train': Icons.train,
  'shop': Icons.storefront,
  'wifi': Icons.wifi,
  'power': Icons.power,
  'dog': Icons.pets,
  'music': Icons.music_note,
  'hidden': Icons.visibility_off,
  'star': Icons.star_outline,
  'warning': Icons.warning_amber,
};

const IconData kFallbackTagIcon = Icons.sell_outlined;

/// Tag name in the app's language, from the catalog.
String spotTagLabel(BuildContext context, SpotTag t) =>
    t.label(Localizations.localeOf(context).languageCode);

IconData spotTagIcon(SpotTag t) =>
    kTagIcons[t.resolved.icon] ?? kFallbackTagIcon;

/// A single multi-select tag chip (the returned [FilterChip] carries [key]).
FilterChip spotTagFilterChip(
  BuildContext context, {
  Key? key,
  required SpotTag tag,
  required bool selected,
  required VoidCallback onToggle,
}) => FilterChip(
  key: key,
  avatar: Icon(spotTagIcon(tag), size: 18),
  label: Text(spotTagLabel(context, tag)),
  selected: selected,
  showCheckmark: false,
  onSelected: (_) => onToggle(),
);

/// Wrap of multi-select chips for all tags. Chip keys are
/// `Key('<keyPrefix><wire>')`.
class SpotTagSelector extends ConsumerWidget {
  const SpotTagSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'tag-',
  });

  final Iterable<SpotTag> selected;
  final ValueChanged<List<SpotTag>> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final set = selected.toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in ref.watch(tagCatalogProvider))
          spotTagFilterChip(
            context,
            key: Key('$keyPrefix${t.wire}'),
            tag: t,
            selected: set.contains(t),
            onToggle: () => onChanged(
              SpotTag.sorted(
                set.contains(t) ? set.difference({t}) : {...set, t},
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only chips for [tags]; renders nothing when empty. [compact] makes
/// them small (map preview).
class SpotTagChips extends ConsumerWidget {
  const SpotTagChips({
    super.key,
    required this.tags,
    this.keyPrefix = 'spotTag-',
    this.compact = false,
  });

  final List<SpotTag> tags;
  final String keyPrefix;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tags.isEmpty) return const SizedBox.shrink();
    ref.watch(tagCatalogProvider); // names and icons may change
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 4 : 8,
      children: [
        for (final t in tags)
          Chip(
            key: Key('$keyPrefix${t.wire}'),
            avatar: Icon(spotTagIcon(t), size: compact ? 14 : 18),
            label: Text(spotTagLabel(context, t)),
            visualDensity: compact ? VisualDensity.compact : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: compact ? Theme.of(context).textTheme.labelSmall : null,
            padding: compact ? EdgeInsets.zero : null,
          ),
      ],
    );
  }
}

/// The tag half of a horizontal filter chip row: a divider, one toggle per
/// catalog tag and a "clear" chip while anything is selected. Returned as a
/// flat list so callers can put it into their own scrolling row; [ref] makes
/// the caller rebuild when the catalog changes.
List<Widget> spotTagFilterItems(
  BuildContext context,
  WidgetRef ref, {
  required String keyPrefix,
  required List<SpotTag> selected,
  required ValueChanged<SpotTag> onToggle,
  required VoidCallback onClear,
  Key? dividerKey,
  Key? clearKey,
  bool withDivider = true,
}) {
  final l = AppLocalizations.of(context);
  return [
    if (withDivider)
      SizedBox(
        key: dividerKey,
        height: 28,
        child: const VerticalDivider(width: 16, thickness: 1),
      ),
    for (final t in ref.watch(tagCatalogProvider))
      spotTagFilterChip(
        context,
        key: Key('$keyPrefix${t.wire}'),
        tag: t,
        selected: selected.contains(t),
        onToggle: () => onToggle(t),
      ),
    if (selected.isNotEmpty)
      ActionChip(
        key: clearKey,
        avatar: const Icon(Icons.clear, size: 18),
        label: Text(l.tagsClear),
        onPressed: onClear,
      ),
  ];
}
