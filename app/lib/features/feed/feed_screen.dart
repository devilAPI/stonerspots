import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'feed_card.dart';
import 'feed_controller.dart';
import 'feed_repository.dart';

String _sortLabel(AppLocalizations l, FeedSort s) => switch (s) {
  FeedSort.newest => l.sortNew,
  FeedSort.top => l.sortTop,
  FeedSort.nearby => l.sortNearby,
};

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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedTitle)),
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
    // Cards stay at a readable width on wide windows, while the scrollable
    // area (and its mouse-wheel/scrollbar) spans the whole pane.
    final gutter = sideGutter(width);
    Widget body;
    if (state.error != null && state.items.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.errorGeneric),
            TextButton(onPressed: ctrl.load, child: Text(l10n.retry)),
          ],
        ),
      );
    } else if (state.loading && state.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.loadedOnce && state.items.isEmpty) {
      body = ListView(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(l10n.noResults)),
        ],
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.symmetric(horizontal: gutter),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.items.length + (state.loadingMore ? 1 : 0),
        itemBuilder: (_, i) => i >= state.items.length
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : FeedCard(item: state.items[i]),
      );
    }

    return Column(
      children: [
        _ChipRow(
          gutter: gutter,
          children: [
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
          gutter: gutter,
          children: spotTagFilterItems(
            context,
            keyPrefix: 'feedTag-',
            selected: state.tags,
            onToggle: ctrl.toggleTag,
            onClear: ctrl.clearTags,
            clearKey: const Key('feedTagsClear'),
            withDivider: false,
          ),
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: ctrl.refresh, child: body),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({super.key, required this.children, this.gutter = 0});
  final List<Widget> children;
  final double gutter;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 12 + gutter, vertical: 4),
      children: [
        for (final c in children)
          Padding(padding: const EdgeInsets.only(right: 8), child: c),
      ],
    ),
  );
}
