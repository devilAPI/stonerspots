import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/back_or_home.dart';
import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_edit_dialogs.dart';
import '../admin/admin_models.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_controller.dart';
import '../reviews/rating_widgets.dart';
import '../reviews/reviews_section.dart';
import 'edit_tags_dialog.dart';
import 'maps_link.dart';
import 'photo_viewer.dart';
import 'spot_api.dart';
import 'spot_link.dart';
import 'spot_location_map.dart';
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
      // pushed: after logging in it pops back to this spot
      context.push('/login');
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

  Future<void> _copyLink() async {
    final copied = AppLocalizations.of(context).linkCopied;
    await Clipboard.setData(
      ClipboardData(text: spotLink(widget.spotId).toString()),
    );
    _snack(copied);
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

  // ---- admin actions ----

  Future<void> _adminEditSpot(Spot spot) async {
    final saved = await showEditSpotDialog(
      context,
      spot: AdminSpot.fromSpot(spot),
    );
    if (saved == null || !mounted) return;
    _snack(AppLocalizations.of(context).adminSpotSaved);
    ref.invalidate(spotDetailProvider(widget.spotId));
  }

  Future<void> _adminToggleLock(Spot spot) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateSpot(spot.id, AdminSpotPatch(locked: !spot.locked));
      _snack(spot.locked ? l.adminSpotUnlocked : l.adminSpotLocked);
      ref.invalidate(spotDetailProvider(widget.spotId));
    } catch (_) {
      _snack(l.errorGeneric);
    }
  }

  Future<void> _adminEditUpdate(FeedItem item) async {
    final saved = await showAdminUpdateDialog(context, item);
    if (saved == true) ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  Future<void> _adminHideUpdate(FeedItem item) async {
    final l = AppLocalizations.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateUpdate(item.id, const AdminUpdatePatch(status: 'hidden'));
      _snack(l.adminUpdateHidden);
      ref.invalidate(spotUpdatesProvider(widget.spotId));
    } catch (_) {
      _snack(l.errorGeneric);
    }
  }

  Future<void> _adminDeleteUpdate(FeedItem item) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.adminRemoveUpdateTitle),
        content: Text(l.adminRemoveUpdateBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const Key('adminUpdateDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.adminRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(adminRepositoryProvider).deleteUpdate(item.id);
      _snack(l.adminUpdateRemoved);
    } catch (e) {
      if (!(e is ApiException && e.status == 404)) _snack(l.errorGeneric);
    }
    ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    ref.watch(authControllerProvider); // keep the session loaded for gating
    final spotAsync = ref.watch(spotDetailProvider(widget.spotId));
    final updates = ref.watch(spotUpdatesProvider(widget.spotId));
    final me = ref.watch(authControllerProvider).value;
    final myId = me?.id;
    final isAdmin = me?.isAdmin ?? false;
    final loaded = spotAsync.value;

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: Text(spotAsync.value?.title ?? l.spotDetailTitle),
        actions: [
          IconButton(
            key: const Key('copySpotLink'),
            tooltip: l.spotCopyLink,
            icon: const Icon(Icons.link),
            onPressed: _copyLink,
          ),
          PopupMenuButton<String>(
            key: const Key('menu'),
            onSelected: (v) {
              switch (v) {
                case 'report':
                  _gated(() => _report('spot', widget.spotId));
                case 'admin-edit':
                  if (loaded != null) _adminEditSpot(loaded);
                case 'admin-lock':
                  if (loaded != null) _adminToggleLock(loaded);
              }
            },
            itemBuilder: (_) => [
              if (isAdmin && loaded != null) ...[
                PopupMenuItem(
                  key: const Key('adminEditSpot'),
                  value: 'admin-edit',
                  child: ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: Text(l.adminEditSpotHere),
                  ),
                ),
                PopupMenuItem(
                  key: const Key('adminLockSpot'),
                  value: 'admin-lock',
                  child: ListTile(
                    leading: Icon(
                      loaded.locked ? Icons.lock_open : Icons.lock_outline,
                    ),
                    title: Text(loaded.locked ? l.adminUnlock : l.adminLock),
                  ),
                ),
                const PopupMenuDivider(),
              ],
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
          void openPhoto(int i) => showPhotoViewer(context, urls, i);
          // A locked spot stays as it is for everyone but admins.
          final canChange = !spot.locked || isAdmin;
          final canEditTags =
              canChange &&
              me != null &&
              (me.isAdmin || (spot.author != null && spot.author!.id == me.id));
          final info = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (spot.locked)
                  Padding(
                    key: const Key('spotLockedNotice'),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock,
                          size: 16,
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: Text(l.spotLockedNotice)),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                RatingBadge(
                  key: const Key('spotRating'),
                  avg: spot.ratingAvg,
                  count: spot.ratingCount,
                ),
                if (spot.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SpotTagChips(tags: spot.tags),
                ],
                if (canEditTags)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('editTags'),
                      onPressed: () => _editTags(spot),
                      icon: const Icon(Icons.sell_outlined),
                      label: Text(l.editTags),
                    ),
                  ),
                const SizedBox(height: 12),
                // Wraps onto further lines instead of overflowing.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonalIcon(
                          key: const Key('like'),
                          onPressed: () => _gated(_toggleLike),
                          icon: Icon(
                            _liked ? Icons.favorite : Icons.favorite_border,
                          ),
                          label: Text(l.like),
                        ),
                        const SizedBox(width: 8),
                        Text(l.likesCount(_likeCount ?? spot.likeCount)),
                        const SizedBox(width: 8),
                      ],
                    ),
                    if (canChange)
                      OutlinedButton.icon(
                        key: const Key('postUpdate'),
                        onPressed: () => _gated(_postUpdate),
                        icon: const Icon(Icons.edit),
                        label: Text(l.postUpdate),
                      ),
                    OutlinedButton.icon(
                      key: const Key('openInMaps'),
                      onPressed: () => _openInMaps(spot),
                      icon: const Icon(Icons.map_outlined),
                      label: Text(l.openInGoogleMaps),
                    ),
                  ],
                ),
                if (spot.description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    spot.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          );
          final timeline = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.updatesTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                updates.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => Text(l.errorGeneric),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(l.updatesNone),
                        )
                      : Column(
                          children: [
                            for (final u in list)
                              UpdateTile(
                                item: u,
                                isMine: myId != null && u.author.id == myId,
                                onEdit: () => _editUpdate(u),
                                onDelete: () => _deleteUpdate(u),
                                onReport: () =>
                                    _gated(() => _report('update', u.id)),
                                onPhotoTap: (i) => showPhotoViewer(context, [
                                  for (final p in u.photos) p.url,
                                ], i),
                                canChangeOwn: canChange,
                                onAdminEdit: isAdmin
                                    ? () => _adminEditUpdate(u)
                                    : null,
                                onAdminHide: isAdmin
                                    ? () => _adminHideUpdate(u)
                                    : null,
                                onAdminDelete: isAdmin
                                    ? () => _adminDeleteUpdate(u)
                                    : null,
                              ),
                          ],
                        ),
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

          Widget locationMap(double height, {double radius = 12}) => SizedBox(
            height: height,
            child: SpotLocationMap(
              lat: spot.lat,
              lon: spot.lon,
              radius: radius,
            ),
          );

          return LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth;
              final landscapePhone = context.isPhoneLandscape;
              if (!landscapePhone && width < kTwoPaneBreakpoint) {
                // Phone portrait: swipeable photos on top, then details and
                // the map. Without photos the map takes the top spot.
                final heroHeight = (width * 3 / 4).clamp(
                  160.0,
                  MediaQuery.sizeOf(context).height * 0.5,
                );
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (urls.isEmpty)
                      locationMap(heroHeight, radius: 0)
                    else
                      SpotHeroCarousel(
                        photoUrls: urls,
                        height: heroHeight,
                        onPhotoTap: openPhoto,
                      ),
                    info,
                    if (urls.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: locationMap((width * 0.6).clamp(200.0, 320.0)),
                      ),
                    const Divider(),
                    reviewsSection,
                    const Divider(),
                    timeline,
                  ],
                );
              }

              // Side by side: map and photos stay visible on the left while
              // the details scroll next to them.
              final mediaWidth = landscapePhone
                  ? (width * 0.4).clamp(220.0, 360.0)
                  : (width * 0.38).clamp(300.0, 560.0);
              final media = SizedBox(
                width: mediaWidth,
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    // where it is first, then what it looks like
                    locationMap((mediaWidth - 24) * 0.75),
                    if (urls.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SpotMediaGallery(photoUrls: urls, onPhotoTap: openPhoto),
                    ],
                  ],
                ),
              );
              // Very wide: updates get their own column.
              final threePane = !context.isPhone && width >= 1280;
              return Row(
                key: Key(threePane ? 'detailThreePane' : 'detailTwoPane'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  media,
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _ReadablePane(
                      children: [
                        info,
                        const Divider(),
                        reviewsSection,
                        if (!threePane) ...[const Divider(), timeline],
                      ],
                    ),
                  ),
                  if (threePane) ...[
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: (width * 0.28).clamp(360.0, 480.0),
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [timeline],
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Scrolling pane whose content stays at a readable width, centred, while
/// the scroll area (mouse wheel, scrollbar) spans the whole pane.
class _ReadablePane extends StatelessWidget {
  const _ReadablePane({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => ListView(
      padding: EdgeInsets.fromLTRB(
        sideGutter(c.maxWidth),
        0,
        sideGutter(c.maxWidth),
        24,
      ),
      children: children,
    ),
  );
}
