import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../core/paging.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../feed/feed_card.dart' show relativeTime;
import 'activity_controller.dart';
import 'activity_models.dart';

/// What happened to the user's own content, newest first. Opening it marks
/// everything shown as read; unread items stay highlighted while it is open.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      ref.read(activityFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(activityFeedProvider);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(l.activityTitle),
      ),
      body: LayoutBuilder(
        builder: (context, c) => _body(context, l, state, c.maxWidth),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l,
    Paged<ActivityItem> state,
    double width,
  ) {
    final ctrl = ref.read(activityFeedProvider.notifier);
    final insets = MediaQuery.paddingOf(context);
    final gutter = sideGutter(width);
    final padding = EdgeInsets.fromLTRB(
      insets.left + gutter,
      GlassAppBar.contentTop(context),
      insets.right + gutter,
      insets.bottom + 16,
    );
    final List<Widget> children;
    if (state.items.isEmpty) {
      children = [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
          child: switch (state) {
            Paged(loading: true) || Paged(loadedOnce: false) => const Center(
              child: CircularProgressIndicator(),
            ),
            Paged(error: != null) => Column(
              key: const Key('activityError'),
              children: [
                Text(l.errorGeneric, textAlign: TextAlign.center),
                TextButton(onPressed: ctrl.load, child: Text(l.retry)),
              ],
            ),
            _ => Column(
              key: const Key('activityEmpty'),
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(l.activityEmpty, textAlign: TextAlign.center),
              ],
            ),
          },
        ),
      ];
    } else {
      // A short first page may not fill the window, so nothing would
      // scroll to trigger the next one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
      children = [
        for (final item in state.items)
          _ActivityTile(key: ValueKey(item.id), item: item),
        if (state.loadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (state.error != null)
          Center(
            child: TextButton(onPressed: ctrl.loadMore, child: Text(l.retry)),
          ),
      ];
    }
    return RefreshIndicator(
      edgeOffset: GlassAppBar.contentTop(context),
      onRefresh: ctrl.refresh,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        children: children,
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({super.key, required this.item});

  final ActivityItem item;

  static IconData _icon(ActivityKind k) => switch (k) {
    ActivityKind.follow => Icons.person_add_alt_1_outlined,
    ActivityKind.comment => Icons.chat_bubble_outline,
    ActivityKind.like => Icons.favorite_border,
    ActivityKind.review => Icons.star_border,
  };

  String _text(AppLocalizations l) {
    final name = item.actor.displayName;
    final spot = item.spot?.title ?? '';
    return switch (item.kind) {
      ActivityKind.follow => l.activityFollow(name),
      ActivityKind.comment => l.activityComment(
        name,
        spot,
        item.commentPreview ?? '',
      ),
      ActivityKind.like => l.activityLike(name, spot),
      ActivityKind.review => l.activityReview(name, spot),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final unread = !item.read;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        key: Key('activity-${item.id}'),
        color: unread ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: unread
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            foregroundColor: unread ? scheme.onPrimary : scheme.onSurface,
            child: Icon(_icon(item.kind), size: 20),
          ),
          title: Text(
            _text(l),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
          ),
          subtitle: Text(relativeTime(item.createdAt)),
          trailing: unread
              ? Icon(
                  Icons.circle,
                  key: const Key('activityUnreadDot'),
                  size: 10,
                  color: scheme.primary,
                )
              : null,
          onTap: () => context.push(item.target),
        ),
      ),
    );
  }
}
