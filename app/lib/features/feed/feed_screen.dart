import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
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

const double _headerHeight = 142;
const double _headerGap = 8;

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scroll = ScrollController();

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

    // Following needs a login; after a logout the feed shows everyone again.
    ref.listen(authControllerProvider.select((a) => a.value?.id), (_, id) {
      if (id == null && ref.read(feedControllerProvider).following) {
        ref.read(feedControllerProvider.notifier).setFollowing(false);
      }
    });

    return Scaffold(
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
    final loggedIn = ref.watch(
      authControllerProvider.select((a) => a.value != null),
    );
    // The list runs under the status bar, the glass header and the shell's
    // glass navigation; [insets] says what those cover.
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
    final top = insets.top + _headerGap + _headerHeight + _headerGap;
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
            child: Text(
              state.following ? l10n.feedFollowingEmpty : l10n.noResults,
              textAlign: TextAlign.center,
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
          top: insets.top + _headerGap,
          left: insets.left + gutter + _headerGap,
          right: insets.right + gutter + _headerGap,
          height: _headerHeight,
          child: GlassSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Text(
                    l10n.feedTitle,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(color: kOnGlass),
                  ),
                ),
                _ChipRow(
                  children: [
                    // first, so narrow phones do not scroll it out of view
                    if (loggedIn)
                      FilterChip(
                        key: const Key('feedFollowing'),
                        label: Text(l10n.feedFollowing),
                        selected: state.following,
                        onSelected: ctrl.setFollowing,
                      ),
                    for (final s in FeedSort.values)
                      ChoiceChip(
                        label: Text(_sortLabel(l10n, s)),
                        selected: state.sort == s,
                        onSelected: (_) => ctrl.setSort(s),
                      ),
                  ],
                ),
                _ChipRow(
                  key: const Key('feedTagRow'),
                  children: spotTagFilterItems(
                    context,
                    ref,
                    keyPrefix: 'feedTag-',
                    selected: state.tags,
                    onToggle: ctrl.toggleTag,
                    onClear: ctrl.clearTags,
                    clearKey: const Key('feedTagsClear'),
                    withDivider: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
  Widget build(BuildContext context) =>
      SizedBox(height: 48, child: GlassChipRow(children: children));
}
