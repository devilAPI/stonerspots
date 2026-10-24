import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'models.dart';

String spotTagLabel(AppLocalizations l, SpotTag t) => switch (t) {
  SpotTag.roof => l.tagRoof,
  SpotTag.seating => l.tagSeating,
  SpotTag.view => l.tagView,
  SpotTag.quiet => l.tagQuiet,
  SpotTag.shade => l.tagShade,
  SpotTag.water => l.tagWater,
  SpotTag.lit => l.tagLit,
};

IconData spotTagIcon(SpotTag t) => switch (t) {
  SpotTag.roof => Icons.roofing,
  SpotTag.seating => Icons.chair_alt,
  SpotTag.view => Icons.landscape,
  SpotTag.quiet => Icons.volume_off,
  SpotTag.shade => Icons.wb_shade,
  SpotTag.water => Icons.water_drop,
  SpotTag.lit => Icons.lightbulb_outline,
};

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
  label: Text(spotTagLabel(AppLocalizations.of(context), tag)),
  selected: selected,
  showCheckmark: false,
  onSelected: (_) => onToggle(),
);

/// Wrap of multi-select chips for all tags. Chip keys are
/// `Key('<keyPrefix><wire>')`.
class SpotTagSelector extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final set = selected.toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in SpotTag.values)
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
class SpotTagChips extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 4 : 8,
      children: [
        for (final t in tags)
          Chip(
            key: Key('$keyPrefix${t.wire}'),
            avatar: Icon(spotTagIcon(t), size: compact ? 14 : 18),
            label: Text(spotTagLabel(l, t)),
            visualDensity: compact ? VisualDensity.compact : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelStyle: compact ? Theme.of(context).textTheme.labelSmall : null,
            padding: compact ? EdgeInsets.zero : null,
          ),
      ],
    );
  }
}

/// The tag half of a horizontal filter chip row: a divider, the seven tag
/// toggles and a "clear" chip while anything is selected. Returned as a flat
/// list so callers can put it into their own scrolling row.
List<Widget> spotTagFilterItems(
  BuildContext context, {
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
    for (final t in SpotTag.values)
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
