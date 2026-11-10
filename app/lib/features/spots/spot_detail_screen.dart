import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/glass.dart';
import '../../core/back_or_home.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../admin/admin_bulk.dart';
import '../admin/admin_edit_dialogs.dart';
import '../admin/admin_models.dart';
import '../admin/admin_repository.dart';
import '../auth/auth_controller.dart';
import '../comments/spot_comments.dart';
import '../map/spots_controller.dart';
import '../reviews/reviews_section.dart';
import '../weather/spot_weather_section.dart';
import 'edit_tags_dialog.dart';
import 'maps_link.dart';
import 'photo_viewer.dart';
import 'spot_api.dart';
import 'spot_detail_sections.dart';
import 'spot_link.dart';
import 'spot_media.dart';
import 'update_actions.dart';
import 'update_composer.dart';
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

  /// Share sheet where the platform has one, otherwise the link is copied.
  Future<void> _share(BuildContext button, String? title) async {
    final copied = AppLocalizations.of(context).linkCopied;
    final link = spotLink(widget.spotId);
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    var shared = false;
    try {
      shared = await ref.read(linkSharerProvider)(
        link,
        title: title,
        origin: origin,
      );
    } catch (_) {}
    if (shared) return;
    await Clipboard.setData(ClipboardData(text: link.toString()));
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

  Future<void> _reloadUpdatesIf(Future<bool> changed) async {
    if (await changed) ref.invalidate(spotUpdatesProvider(widget.spotId));
  }

  Future<void> _editUpdate(FeedItem item) =>
      _reloadUpdatesIf(editOwnUpdate(context, item));

  Future<void> _deleteUpdate(FeedItem item) =>
      _reloadUpdatesIf(deleteOwnUpdate(context, ref, item));

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

  Future<void> _adminDeleteSpot(Spot spot) async {
    final l = AppLocalizations.of(context);
    if (!await confirmAdminDelete(
      context,
      title: l.adminDeleteSpotsTitle(1),
      body: l.adminDeleteSpotsBody,
    )) {
      return;
    }
    try {
      await ref.read(adminRepositoryProvider).deleteSpot(spot.id);
    } catch (_) {
      _snack(l.errorGeneric);
      return;
    }
    if (!mounted) return;
    _snack(l.adminSpotDeleted);
    ref.read(spotsControllerProvider.notifier).retry(); // off the map
    if (GoRouter.maybeOf(context) == null) {
      Navigator.maybePop(context);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _adminEditUpdate(FeedItem item) =>
      _reloadUpdatesIf(adminEditUpdate(context, item));

  Future<void> _adminHideUpdate(FeedItem item) =>
      _reloadUpdatesIf(adminHideUpdate(context, ref, item));

  Future<void> _adminDeleteUpdate(FeedItem item) =>
      _reloadUpdatesIf(adminDeleteUpdate(context, ref, item));

  Future<void> _adminEditUpdates() async {
    final list = ref.read(spotUpdatesProvider(widget.spotId)).value;
    if (list == null || list.isEmpty) return;
    await _reloadUpdatesIf(adminEditOneOf(context, list));
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
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: const BackOrHomeButton(),
        title: Text(spotAsync.value?.title ?? l.spotDetailTitle),
        actions: [
          Builder(
            builder: (button) => IconButton(
              key: const Key('shareSpot'),
              tooltip: l.spotShare,
              icon: Icon(Icons.adaptive.share),
              onPressed: () => _share(button, spotAsync.value?.title),
            ),
          ),
          SpotDetailMenu(
            spot: loaded,
            isAdmin: isAdmin,
            hasUpdates: updates.value?.isNotEmpty ?? false,
            onSelected: (v) {
              switch (v) {
                case 'report':
                  _gated(() => _report('spot', widget.spotId));
                case 'admin-edit':
                  if (loaded != null) _adminEditSpot(loaded);
                case 'admin-lock':
                  if (loaded != null) _adminToggleLock(loaded);
                case 'admin-updates':
                  _adminEditUpdates();
                case 'admin-delete':
                  if (loaded != null) _adminDeleteSpot(loaded);
              }
            },
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
          final info = SpotInfoSection(
            spot: spot,
            liked: _liked,
            likeCount: _likeCount ?? spot.likeCount,
            canChange: canChange,
            canEditTags: canEditTags,
            onLike: () => _gated(_toggleLike),
            onEditTags: () => _editTags(spot),
            onPostUpdate: () => _gated(_postUpdate),
            onOpenInMaps: () => _openInMaps(spot),
          );
          // Its own section, heading included; it hides itself (divider and
          // all) while loading and when the service fails.
          final weather = SpotWeatherSection(
            spotId: spot.id,
            lat: spot.lat,
            lon: spot.lon,
            title: l.weatherTitle,
            dividerAbove: true,
            padding: const EdgeInsets.all(16),
          );
          final timeline = SpotUpdatesSection(
            updates: updates,
            myId: myId,
            isAdmin: isAdmin,
            canChange: canChange,
            onEdit: _editUpdate,
            onDelete: _deleteUpdate,
            onReport: (u) => _gated(() => _report('update', u.id)),
            onAdminEdit: _adminEditUpdate,
            onAdminHide: _adminHideUpdate,
            onAdminDelete: _adminDeleteUpdate,
          );

          final reviewsSection = ReviewsSection(
            spotId: widget.spotId,
            gate: _gated,
            onReport: (id) => _report('review', id),
            onChanged: () => ref.invalidate(spotDetailProvider(widget.spotId)),
          );

          final commentsSection = SpotComments(
            spotId: spot.id,
            count: spot.commentCount,
            canWrite: canChange,
          );

          return SpotDetailLayout(
            spot: spot,
            photoUrls: urls,
            onPhotoTap: openPhoto,
            info: info,
            weather: weather,
            reviews: reviewsSection,
            updates: timeline,
            comments: commentsSection,
          );
        },
      ),
    );
  }
}
