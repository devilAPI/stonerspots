import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/back_or_home.dart';
import '../../core/glass.dart';
import '../../core/models.dart';
import '../../core/net_photo.dart';
import '../../core/paging.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../feed/satellite_thumb.dart';
import '../reviews/rating_widgets.dart';
import 'saved_controller.dart';
import 'saved_lists_screen.dart';

/// The spots of one list.
class SavedListScreen extends ConsumerStatefulWidget {
  const SavedListScreen({super.key, required this.listId});

  final int listId;

  @override
  ConsumerState<SavedListScreen> createState() => _SavedListScreenState();
}

class _SavedListScreenState extends ConsumerState<SavedListScreen> {
  final _scroll = ScrollController();

  SavedListSpotsController get _controller =>
      ref.read(savedListSpotsProvider(widget.listId).notifier);

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
    if (_scroll.position.extentAfter < 400) _controller.loadMore();
  }

  Future<void> _remove(Spot spot) async {
    final failed = AppLocalizations.of(context).errorGeneric;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _controller.remove(spot);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  void _leave() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/saved');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(savedListProvider(widget.listId)).value;
    final page = ref.watch(savedListSpotsProvider(widget.listId));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(list?.title(l) ?? ''),
        actions: [
          if (list != null && !list.isDefault)
            ListActionsMenu(
              key: const Key('listMenu'),
              list: list,
              onDeleted: _leave,
            ),
        ],
      ),
      body: _body(l, page),
    );
  }

  Widget _body(AppLocalizations l, Paged<Spot> page) {
    if (page.error != null && page.items.isEmpty) {
      final error = page.error;
      final gone = error is ApiException && error.status == 404;
      return _Centered(
        children: [
          Text(gone ? l.savedListGone : l.errorGeneric),
          if (!gone)
            TextButton(onPressed: _controller.loadFirst, child: Text(l.retry)),
        ],
      );
    }
    if (page.items.isEmpty && !page.loadedOnce) {
      return const _Centered(children: [CircularProgressIndicator()]);
    }
    if (page.items.isEmpty) {
      return _Centered(
        key: const Key('savedListEmpty'),
        children: [
          Icon(
            Icons.bookmark_border,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(l.savedListEmpty, textAlign: TextAlign.center),
        ],
      );
    }
    // A short first page may not fill the window, so nothing would scroll
    // to trigger the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _onScroll();
    });
    final satellite = page.items.any((s) => s.coverUrl == null);
    return LayoutBuilder(
      builder: (context, c) => RefreshIndicator(
        edgeOffset: GlassAppBar.contentTop(context),
        onRefresh: _controller.refresh,
        child: SideInsetsHandled(
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: savedPagePadding(context, c.maxWidth),
            itemCount:
                page.items.length +
                (page.loadingMore ? 1 : 0) +
                (satellite ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= page.items.length) {
                if (page.loadingMore && i == page.items.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                // the thumbnails are too small to carry it themselves
                return const SatelliteCredit(key: Key('satelliteCredit'));
              }
              final spot = page.items[i];
              return _SpotRow(
                key: ValueKey(spot.id),
                spot: spot,
                onRemove: () => _remove(spot),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Centred below the glass bar.
class _Centered extends StatelessWidget {
  const _Centered({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      32,
      GlassAppBar.contentTop(context),
      32,
      MediaQuery.paddingOf(context).bottom,
    ),
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({super.key, required this.spot, required this.onRemove});

  final Spot spot;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cover = spot.coverUrl;
    return ListTile(
      key: Key('savedSpot-${spot.id}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 56,
          child: cover == null
              ? SatelliteThumb(lat: spot.lat, lon: spot.lon)
              : NetPhoto(cover, decodeWidth: 56),
        ),
      ),
      title: Text(spot.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              l.likesCount(spot.likeCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          RatingBadge(avg: spot.ratingAvg, count: spot.ratingCount),
        ],
      ),
      trailing: IconButton(
        key: Key('removeSpot-${spot.id}'),
        tooltip: l.savedRemoveSpot,
        icon: const Icon(Icons.bookmark_remove_outlined),
        onPressed: onRemove,
      ),
      onTap: () => context.push('/spot/${spot.id}'),
    );
  }
}
