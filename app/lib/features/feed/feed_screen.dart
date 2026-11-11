import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../core/tag_catalog.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../spots/update_actions.dart';
import 'feed_card.dart';
import 'feed_controller.dart';
import 'feed_repository.dart';

String _sortLabel(AppLocalizations l, FeedSort s) => switch (s) {
  FeedSort.newest => l.sortNew,
  FeedSort.top => l.sortTop,
  FeedSort.nearby => l.sortNearby,
};

IconData _sortIcon(FeedSort s) => switch (s) {
  FeedSort.newest => Icons.schedule,
  FeedSort.top => Icons.local_fire_department_outlined,
  FeedSort.nearby => Icons.near_me_outlined,
};

/// Under the title: the sort as glass tabs and, while any filter is on, a
/// row of them to remove one by one.
const double _chipRowHeight = 44;
const double _chipRowGap = 6;
const double _headerGap = 8;
const double _headerMaxWidth = 520;

double _headerHeight(FeedState s) =>
    kGlassControlSize + (s.filterCount > 0 ? _chipRowGap + _chipRowHeight : 0);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final TabController _sortTabs = TabController(
    length: FeedSort.values.length,
    initialIndex: ref.read(feedControllerProvider).sort.index,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    Future.microtask(() {
      if (mounted) ref.read(feedControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sortTabs.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400) {
      ref.read(feedControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(feedControllerProvider);

    ref.listen(feedControllerProvider.select((s) => s.locationDenied), (
      _,
      denied,
    ) {
      if (denied) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.locationDenied)));
      }
    });

    // the sort can change by itself (nearby without a location)
    ref.listen(feedControllerProvider.select((s) => s.sort), (_, sort) {
      if (_sortTabs.index != sort.index) _sortTabs.animateTo(sort.index);
    });

    // Following needs a login; after a logout the feed shows everyone again.
    ref.listen(authControllerProvider.select((a) => a.value?.id), (_, id) {
      if (id == null && ref.read(feedControllerProvider).following) {
        ref.read(feedControllerProvider.notifier).setFollowing(false);
      }
    });

    return Scaffold(
      // like every page: a floating title, the feed fades out beneath it
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Text(l10n.feedTitle),
        actions: [_FilterButton(count: state.filterCount)],
      ),
      // Gutter from the space the feed actually gets (the nav rail takes
      // part of the window), not from the window width.
      body: LayoutBuilder(
        builder: (context, c) => _buildBody(context, state, c.maxWidth),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FeedState state, double width) {
    final l10n = AppLocalizations.of(context);
    final ctrl = ref.read(feedControllerProvider.notifier);
    // The list runs under the status bar, the title, the chips and the
    // shell's glass navigation; [insets] says what the bars cover (the
    // Scaffold counts the title in its top).
    final insets = MediaQuery.paddingOf(context);
    width -= insets.left + insets.right;
    // Phones get one column; tablets/desktops a grid as wide as the pane
    // allows. Content stays centred at a readable width, while the scrollable
    // area (and its mouse-wheel/scrollbar) spans the whole pane.
    final columns = context.isPhone ? 1 : feedColumns(width);
    final grid = columns > 1;
    final gutter = sideGutter(
      width,
      maxWidth: grid ? kFeedGridMaxWidth : kContentMaxWidth,
    );
    final cardLayout = context.isPhoneLandscape
        ? FeedCardLayout.side
        : FeedCardLayout.stacked;
    final rows = grid
        ? (state.items.length / columns).ceil()
        : state.items.length;
    final top = insets.top + _headerHeight(state) + _headerGap;
    final page = EdgeInsets.only(
      left: insets.left,
      right: insets.right,
      top: top,
      bottom: insets.bottom,
    );
    Widget body;
    if (state.error != null && state.items.isEmpty) {
      body = Padding(
        padding: page,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.errorGeneric),
              TextButton(onPressed: ctrl.load, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    } else if (state.loading && state.items.isEmpty) {
      body = Padding(
        padding: page,
        child: const Center(child: CircularProgressIndicator()),
      );
    } else if (state.loadedOnce && state.items.isEmpty) {
      body = ListView(
        padding: page.add(EdgeInsets.symmetric(horizontal: gutter)),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(switch (state) {
              FeedState(following: true, filterCount: 1) =>
                l10n.feedFollowingEmpty,
              FeedState(filterCount: > 0) => l10n.feedFilteredEmpty,
              _ => l10n.noResults,
            }, textAlign: TextAlign.center),
          ),
          if (state.filterCount > 0)
            Center(
              child: TextButton(
                key: const Key('feedEmptyReset'),
                onPressed: ctrl.clearFilters,
                child: Text(l10n.feedFiltersReset),
              ),
            ),
        ],
      );
    } else {
      // A short first page (wide grid) may not fill the pane, so nothing
      // would scroll to trigger the next one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _onScroll();
      });
      body = ListView.builder(
        controller: _scroll,
        padding: page.add(
          EdgeInsets.symmetric(
            horizontal: gutter + (grid ? 6 : 0),
            vertical: grid ? 6 : 0,
          ),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows + (state.loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= rows) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!grid) {
            final item = state.items[i];
            return FeedCard(
              item: item,
              layout: cardLayout,
              menu: _CardMenu(item),
            );
          }
          return _GridRow(
            items: state.items.skip(i * columns).take(columns).toList(),
            columns: columns,
          );
        },
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RefreshIndicator(
            onRefresh: ctrl.refresh,
            edgeOffset: top,
            child: body,
          ),
        ),
        Positioned(
          top: insets.top,
          left: insets.left + gutter + _headerGap,
          right: insets.right + gutter + _headerGap,
          // a compact group over the middle, not a bar across wide windows
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _headerMaxWidth),
              child: _header(context, state, ctrl),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, FeedState state, FeedController ctrl) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassTabs(
          key: const Key('feedSort'),
          controller: _sortTabs,
          onTap: (i) => ctrl.setSort(FeedSort.values[i]),
          tabs: [
            for (final s in FeedSort.values)
              Tab(
                key: Key('feedSort-${s.name}'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_sortIcon(s), size: 18),
                    const SizedBox(width: 6),
                    Text(_sortLabel(l10n, s)),
                  ],
                ),
              ),
          ],
        ),
        if (state.filterCount > 0) ...[
          const SizedBox(height: _chipRowGap),
          SizedBox(
            width: double.infinity,
            child: _ActiveFilters(state: state),
          ),
        ],
      ],
    );
  }
}

/// The title's filter button; a badge counts the filters that are on.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('feedFilters'),
    tooltip: AppLocalizations.of(context).feedFilters,
    icon: Badge(
      isLabelVisible: count > 0,
      backgroundColor: Theme.of(context).colorScheme.primary,
      textColor: Theme.of(context).colorScheme.onPrimary,
      label: Text('$count'),
      child: const Icon(Icons.tune),
    ),
    onPressed: () => showFeedFilters(context),
  );
}

/// The filters that are on, each with an x; a tap on one opens the sheet.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.state});
  final FeedState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final ctrl = ref.read(feedControllerProvider.notifier);
    void open() => showFeedFilters(context);
    final radius = state.radiusKm;
    return _ChipRow(
      key: const Key('feedActiveFilters'),
      children: [
        if (radius != null)
          InputChip(
            key: const Key('feedActive-radius'),
            avatar: const Icon(Icons.radar),
            label: Text(l.feedRadiusChip(radius)),
            onPressed: open,
            onDeleted: () => ctrl.setRadius(null),
          ),
        if (state.following)
          InputChip(
            key: const Key('feedActive-following'),
            avatar: const Icon(Icons.people_outline),
            label: Text(l.feedFollowing),
            onPressed: open,
            onDeleted: () => ctrl.setFollowing(false),
          ),
        for (final t in state.tags)
          InputChip(
            key: Key('feedActive-${t.wire}'),
            avatar: Icon(spotTagIcon(t)),
            label: Text(spotTagLabel(context, t)),
            onPressed: open,
            onDeleted: () => ctrl.toggleTag(t),
          ),
        if (state.filterCount > 1)
          ActionChip(
            key: const Key('feedActive-reset'),
            avatar: const Icon(Icons.clear),
            label: Text(l.feedFiltersReset),
            onPressed: ctrl.clearFilters,
          ),
      ],
    );
  }
}

/// Opens the feed's filters: distance from the user, people followed, tags.
/// They apply as they change; the feed behind updates.
Future<void> showFeedFilters(BuildContext context) => showGlassSheet<void>(
  context: context,
  radius: 32,
  // above the floating tab bar, which lives outside this tab's navigator
  useRootNavigator: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (_) => const FeedFilterSheet(),
);

class FeedFilterSheet extends ConsumerWidget {
  const FeedFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final state = ref.watch(feedControllerProvider);
    final ctrl = ref.read(feedControllerProvider.notifier);
    final loggedIn = ref.watch(
      authControllerProvider.select((a) => a.value != null),
    );
    final section = text.titleSmall?.copyWith(
      color: kOnGlass,
      fontWeight: FontWeight.w600,
    );
    final muted = text.bodySmall?.copyWith(
      color: kOnGlass.withValues(alpha: 0.7),
    );
    final radius = state.radiusKm;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: kOnGlass),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.feedFilters,
                    style: text.titleLarge?.copyWith(color: kOnGlass),
                  ),
                ),
                TextButton(
                  key: const Key('feedFiltersReset'),
                  onPressed: state.filterCount > 0 ? ctrl.clearFilters : null,
                  child: Text(l.feedFiltersReset),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(l.feedRadius, style: section)),
                Text(
                  radius == null
                      ? l.feedRadiusAnywhere
                      : l.feedRadiusKm(radius),
                  key: const Key('feedRadiusValue'),
                  style: section,
                ),
              ],
            ),
            Text(l.feedRadiusHint, style: muted),
            _RadiusSlider(km: radius, onChanged: ctrl.setRadius),
            if (loggedIn) ...[
              SwitchListTile(
                key: const Key('feedFollowing'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.feedFollowingOnly, style: section),
                value: state.following,
                onChanged: ctrl.setFollowing,
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            Text(l.tagsTitle, style: section),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in ref.watch(tagCatalogProvider))
                  spotTagFilterChip(
                    context,
                    key: Key('feedTag-${t.wire}'),
                    tag: t,
                    selected: state.tags.contains(t),
                    onToggle: () => ctrl.toggleTag(t),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('feedFiltersDone'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l.feedFiltersDone),
            ),
          ],
        ),
      ),
    );
  }
}

/// The radius as a slider over [FeedController.radiusSteps], "anywhere" at
/// the far end. Reports once the finger lets go, not on every step.
class _RadiusSlider extends StatefulWidget {
  const _RadiusSlider({required this.km, required this.onChanged});
  final int? km;
  final ValueChanged<int?> onChanged;

  @override
  State<_RadiusSlider> createState() => _RadiusSliderState();
}

class _RadiusSliderState extends State<_RadiusSlider> {
  static const _steps = FeedController.radiusSteps;
  double? _dragging;

  static double _indexOf(int? km) =>
      (km == null ? _steps.length : _steps.indexOf(km)).toDouble();

  static int? _kmAt(double i) =>
      i.round() >= _steps.length ? null : _steps[i.round()];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final value = _dragging ?? _indexOf(widget.km);
    final km = _kmAt(value);
    return Slider(
      key: const Key('feedRadius'),
      value: value,
      max: _steps.length.toDouble(),
      divisions: _steps.length,
      label: km == null ? l.feedRadiusAnywhere : l.feedRadiusKm(km),
      onChanged: (v) => setState(() => _dragging = v),
      onChangeEnd: (v) {
        setState(() => _dragging = null);
        widget.onChanged(_kmAt(v));
      },
    );
  }
}

/// One row of the feed grid: cards share the row's height (the tallest
/// card's), so their pictures and likes line up.
class _GridRow extends StatelessWidget {
  const _GridRow({required this.items, required this.columns});
  final List<FeedItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var j = 0; j < columns; j++)
          Expanded(
            child: j < items.length
                ? FeedCard(
                    item: items[j],
                    layout: FeedCardLayout.tile,
                    margin: const EdgeInsets.all(6),
                    menu: _CardMenu(items[j]),
                  )
                : const SizedBox.shrink(),
          ),
      ],
    ),
  );
}

/// Edit / delete actions on a card's update; reloads the feed after a change.
class _CardMenu extends ConsumerWidget {
  const _CardMenu(this.item);
  final FeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => UpdateMenu(
    item: item,
    onChanged: () => ref.read(feedControllerProvider.notifier).refresh(),
  );
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _chipRowHeight,
    child: GlassSurface(
      radius: _chipRowHeight / 2,
      child: GlassChipRow(children: children),
    ),
  );
}
