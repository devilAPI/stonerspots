import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../feed/satellite_thumb.dart';
import '../reviews/rating_widgets.dart';
import '../reviews/reviews_section.dart';
import 'edit_tags_dialog.dart';
import 'maps_link.dart';
import 'photo_viewer.dart';
import 'spot_api.dart';
import 'spot_media.dart';
import 'update_composer.dart';
import 'update_tile.dart';
import 'updates_repository.dart';

final spotDetailProvider = FutureProvider.autoDispose.family<Spot, int>(
  (ref, id) => ref.watch(spotApiProvider).getSpot(id),
);

final spotUpdatesProvider = FutureProvider.autoDispose
    .family<List<FeedItem>, int>(
      (ref, id) => ref.watch(spotUpdatesRepositoryProvider).listForSpot(id),
    );

class SpotDetailScreen extends ConsumerStatefulWidget {
  const SpotDetailScreen({super.key, required this.spotId});

  final int spotId;

  @override
  ConsumerState<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends ConsumerState<SpotDetailScreen> {
  bool _liked = false;
  int? _likeCount;

  Future<void> _openInMaps(Spot spot) async {
    final errorText = AppLocalizations.of(context).errorGeneric;
    var opened = false;
    try {
      opened = await ref.read(urlLauncherProvider)(
        googleMapsUri(spot.lat, spot.lon),
      );
    } catch (_) {}
    if (!opened) _snack(errorText);
  }

  /// Runs [action] if logged in, otherwise sends the user to the login page.
  void _gated(VoidCallback action) {
    if (ref.read(authControllerProvider).value == null) {
      final here = GoRouterState.of(context).uri.toString();
      context.push('/login?from=${Uri.encodeComponent(here)}');
      return;
    }
    action();
  }

  Future<void> _toggleLike() async {
    final errorText = AppLocalizations.of(context).errorGeneric;
    final want = !_liked;
    try {
      final r = await ref
          .read(spotApiProvider)
          .setLike(widget.spotId, liked: want);
      if (mounted) {
        setState(() {
          _liked = r.liked;
          _likeCount = r.likeCount;
        });
      }
    } catch (_) {
      _snack(errorText);
    }
  }

  Future<void> _editTags(Spot spot) async {
    final saved = await showEditTagsDialog(
      context,
      spotId: spot.id,
      initial: spot.tags,
    );
    if (saved != null) ref.invalidate(spotDetailProvider(widget.spotId));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _report(String type, int id) async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.report),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: l.reportReason),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l.report),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    try {
      await ref.read(spotApiProvider).report(type, id, reason);
    } catch (_) {
      _snack(l.errorGeneric);
    }
  }

  Future<void> _postUpdate() async {
    final posted = await showUpdateComposer(context, spotId: widget.spotId);
    if (posted == true) ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  Future<void> _editUpdate(FeedItem item) async {
    final saved = await showUpdateComposer(
      context,
      spotId: widget.spotId,
      editing: item,
    );
    if (saved == true) ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  Future<void> _deleteUpdate(FeedItem item) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.updateDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('updateDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.updateDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(spotUpdatesRepositoryProvider).delete(item.id);
      ref.invalidate(spotUpdatesProvider(widget.spotId));
    } catch (_) {
      _snack(l.errorGeneric);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.watch(authControllerProvider); // keep the session loaded for gating
    final spotAsync = ref.watch(spotDetailProvider(widget.spotId));
    final updates = ref.watch(spotUpdatesProvider(widget.spotId));
    final me = ref.watch(authControllerProvider).value;
    final myId = me?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(spotAsync.value?.title ?? l.spotDetailTitle),
        actions: [
          PopupMenuButton<String>(
            key: const Key('menu'),
            onSelected: (v) {
              if (v == 'report') {
                _gated(() => _report('spot', widget.spotId));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'report', child: Text(l.report)),
            ],
          ),
        ],
      ),
      body: spotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.errorGeneric),
              TextButton(
                onPressed: () =>
                    ref.invalidate(spotDetailProvider(widget.spotId)),
                child: Text(l.retry),
              ),
            ],
          ),
        ),
        data: (spot) {
          final items = updates.value ?? const <FeedItem>[];
          final urls = validPhotoUrls([
            if (spot.coverUrl != null) spot.coverUrl!,
            for (final i in items)
              for (final p in i.photos)
                if (p.url != spot.coverUrl) p.url,
          ]);
          // user photos first, then the spot seen from above
          final gallery = SpotMediaStrip(
            photoUrls: urls,
            lat: spot.lat,
            lon: spot.lon,
            onPhotoTap: (i) => showPhotoViewer(context, urls, i),
          );
          final info = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    RatingBadge(
                      key: const Key('spotRating'),
                      avg: spot.ratingAvg,
                      count: spot.ratingCount,
                    ),
                  ],
                ),
                if (spot.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SpotTagChips(tags: spot.tags),
                ],
                if (me != null &&
                    (me.isAdmin ||
                        (spot.author != null && spot.author!.id == me.id)))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('editTags'),
                      onPressed: () => _editTags(spot),
                      icon: const Icon(Icons.sell_outlined),
                      label: Text(l.editTags),
                    ),
                  ),
                if (spot.description.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(spot.description),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      key: const Key('like'),
                      onPressed: () => _gated(_toggleLike),
                      icon: Icon(
                        _liked ? Icons.favorite : Icons.favorite_border,
                      ),
                      label: Text(l.like),
                    ),
                    const SizedBox(width: 12),
                    Text(l.likesCount(_likeCount ?? spot.likeCount)),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('postUpdate'),
                  onPressed: () => _gated(_postUpdate),
                  icon: const Icon(Icons.edit),
                  label: Text(l.postUpdate),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('openInMaps'),
                  onPressed: () => _openInMaps(spot),
                  icon: const Icon(Icons.map_outlined),
                  label: Text(l.openInGoogleMaps),
                ),
              ],
            ),
          );
          final timeline = updates.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.errorGeneric),
            ),
            data: (list) => Column(
              children: [
                for (final u in list)
                  UpdateTile(
                    item: u,
                    isMine: myId != null && u.author.id == myId,
                    onEdit: () => _editUpdate(u),
                    onDelete: () => _deleteUpdate(u),
                    onReport: () => _gated(() => _report('update', u.id)),
                    onPhotoTap: (i) => showPhotoViewer(context, [
                      for (final p in u.photos) p.url,
                    ], i),
                  ),
              ],
            ),
          );

          final reviewsSection = ReviewsSection(
            spotId: widget.spotId,
            gate: _gated,
            onReport: (id) => _report('review', id),
            onChanged: () => ref.invalidate(spotDetailProvider(widget.spotId)),
          );

          if (context.twoPane) {
            // Wide window / landscape phone: pictures stay visible on the left
            // while details and updates scroll on the right.
            return Row(
              key: const Key('detailTwoPane'),
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (var i = 0; i < urls.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            key: Key('galleryPhoto_$i'),
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showPhotoViewer(context, urls, i),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: CachedNetworkImage(
                                  imageUrl: urls[i],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ClipRRect(
                        key: const Key('satelliteTile'),
                        borderRadius: BorderRadius.circular(8),
                        child: SatelliteThumb(lat: spot.lat, lon: spot.lon),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 6,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      info,
                      const Divider(),
                      reviewsSection,
                      const Divider(),
                      timeline,
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              gallery,
              info,
              const Divider(),
              reviewsSection,
              const Divider(),
              timeline,
            ],
          );
        },
      ),
    );
  }
}
