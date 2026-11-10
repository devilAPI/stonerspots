import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/glass.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/spot_tag_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../reviews/rating_widgets.dart';
import '../saved/save_spot_button.dart';
import '../users/author_link.dart';
import '../zones/zone_status.dart';
import 'photo_viewer.dart';
import 'spot_location_map.dart';
import 'spot_media.dart';
import 'update_tile.dart';

// The parts of the spot page: its menu, the details, the updates and how
// the sections are laid out for the screen. The page wires them up.

/// The ⋮ menu of the spot page: the admin's actions, then "Report". Picks
/// 'report', 'admin-edit', 'admin-lock', 'admin-updates' or 'admin-delete'.
class SpotDetailMenu extends StatelessWidget {
  const SpotDetailMenu({
    super.key,
    required this.spot,
    required this.isAdmin,
    required this.hasUpdates,
    required this.onSelected,
  });

  /// Null while it loads (only "Report" then).
  final Spot? spot;
  final bool isAdmin;
  final bool hasUpdates;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final spot = this.spot;
    return PopupMenuButton<String>(
      key: const Key('menu'),
      onSelected: onSelected,
      itemBuilder: (_) => [
        if (isAdmin && spot != null) ...[
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
              leading: Icon(spot.locked ? Icons.lock_open : Icons.lock_outline),
              title: Text(spot.locked ? l.adminUnlock : l.adminLock),
            ),
          ),
          if (hasUpdates)
            PopupMenuItem(
              key: const Key('adminEditUpdates'),
              value: 'admin-updates',
              child: ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l.adminEditUpdates),
              ),
            ),
          PopupMenuItem(
            key: const Key('adminDeleteSpot'),
            value: 'admin-delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                l.adminDeleteSpot,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(
          key: const Key('reportSpot'),
          value: 'report',
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(l.report),
          ),
        ),
      ],
    );
  }
}

/// Title, owner, stats, tags, the action buttons and the description.
class SpotInfoSection extends StatelessWidget {
  const SpotInfoSection({
    super.key,
    required this.spot,
    required this.liked,
    required this.likeCount,
    required this.canChange,
    required this.canEditTags,
    required this.onLike,
    required this.onEditTags,
    required this.onPostUpdate,
    required this.onOpenInMaps,
  });

  final Spot spot;
  final bool liked;
  final int likeCount;

  /// Not locked, or an admin: updates can be posted.
  final bool canChange;
  final bool canEditTags;
  final VoidCallback onLike;
  final VoidCallback onEditTags;
  final VoidCallback onPostUpdate;
  final VoidCallback onOpenInMaps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(spot.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          SpotOwnerLine(author: spot.author),
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
          const SizedBox(height: 6),
          Wrap(
            key: const Key('spotStats'),
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l.likesCount(likeCount),
                    key: const Key('spotLikeCount'),
                  ),
                ],
              ),
              RatingBadge(
                key: const Key('spotRating'),
                avg: spot.ratingAvg,
                count: spot.ratingCount,
              ),
              ZoneStatusChip(lat: spot.lat, lon: spot.lon),
            ],
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
                onPressed: onEditTags,
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
              FilledButton.tonalIcon(
                key: const Key('like'),
                onPressed: onLike,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                label: Text(liked ? l.liked : l.like),
              ),
              SaveSpotButton(spotId: spot.id),
              if (canChange)
                OutlinedButton.icon(
                  key: const Key('postUpdate'),
                  onPressed: onPostUpdate,
                  icon: const Icon(Icons.edit),
                  label: Text(l.postUpdate),
                ),
              OutlinedButton.icon(
                key: const Key('openInMaps'),
                onPressed: onOpenInMaps,
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
  }
}

/// The spot's updates, newest first, with what the viewer may do to each.
class SpotUpdatesSection extends StatelessWidget {
  const SpotUpdatesSection({
    super.key,
    required this.updates,
    required this.myId,
    required this.isAdmin,
    required this.canChange,
    required this.onEdit,
    required this.onDelete,
    required this.onReport,
    required this.onAdminEdit,
    required this.onAdminHide,
    required this.onAdminDelete,
  });

  final AsyncValue<List<FeedItem>> updates;
  final int? myId;
  final bool isAdmin;
  final bool canChange;
  final ValueChanged<FeedItem> onEdit;
  final ValueChanged<FeedItem> onDelete;
  final ValueChanged<FeedItem> onReport;
  final ValueChanged<FeedItem> onAdminEdit;
  final ValueChanged<FeedItem> onAdminHide;
  final ValueChanged<FeedItem> onAdminDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.updatesTitle, style: Theme.of(context).textTheme.titleLarge),
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
                          key: ValueKey('update-${u.id}'),
                          item: u,
                          isMine: myId != null && u.author.id == myId,
                          onEdit: () => onEdit(u),
                          onDelete: () => onDelete(u),
                          onReport: () => onReport(u),
                          onPhotoTap: (i) => showPhotoViewer(context, [
                            for (final p in u.photos) p.url,
                          ], i),
                          canChangeOwn: canChange,
                          onAdminEdit: isAdmin ? () => onAdminEdit(u) : null,
                          onAdminHide: isAdmin ? () => onAdminHide(u) : null,
                          onAdminDelete: isAdmin
                              ? () => onAdminDelete(u)
                              : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The sections arranged for the screen: one column on a phone (photos or
/// the map on top), the map and photos beside the details when wider, and
/// the updates in a third column when very wide.
class SpotDetailLayout extends StatelessWidget {
  const SpotDetailLayout({
    super.key,
    required this.spot,
    required this.photoUrls,
    required this.onPhotoTap,
    required this.info,
    required this.weather,
    required this.reviews,
    required this.updates,
    required this.comments,
  });

  final Spot spot;
  final List<String> photoUrls;
  final ValueChanged<int> onPhotoTap;
  final Widget info, weather, reviews, updates, comments;

  Widget _locationMap(double height, {double radius = 12}) => SizedBox(
    height: height,
    child: SpotLocationMap(lat: spot.lat, lon: spot.lon, radius: radius),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final urls = photoUrls;
    final openPhoto = onPhotoTap;
    final locationMap = _locationMap;
    final reviewsSection = reviews;
    final timeline = updates;
    final commentsSection = comments;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final barBottom = GlassAppBar.contentTop(context);
        final landscapePhone = context.isPhoneLandscape;
        if (!landscapePhone && width < kTwoPaneBreakpoint) {
          // Phone portrait: swipeable photos on top, then details and
          // the map. Without photos the map takes the top spot.
          final heroHeight = (width * 3 / 4).clamp(
            160.0,
            MediaQuery.sizeOf(context).height * 0.5,
          );
          return ListView(
            // the hero runs under the glass app bar
            padding: EdgeInsets.zero.copyWith(bottom: 24),
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
              weather,
              if (urls.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // styled like the other sections' headings;
                      // only here, where the map is one section of
                      // a single column
                      Text(
                        l.mapTitle,
                        key: const Key('mapHeading'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      locationMap((width * 0.6).clamp(200.0, 320.0)),
                    ],
                  ),
                ),
              ],
              const Divider(),
              reviewsSection,
              const Divider(),
              timeline,
              const Divider(),
              commentsSection,
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
            // the map's top in line with the title of the other pane
            padding: EdgeInsets.fromLTRB(12, barBottom + 16, 12, 12),
            children: [
              // where it is first, then what it looks like; no
              // heading: next to the details it speaks for itself
              locationMap((mediaWidth - 24) * 0.75),
              if (urls.isNotEmpty) ...[
                const SizedBox(height: 8),
                SpotMediaGallery(photoUrls: urls, onPhotoTap: openPhoto),
              ],
            ],
          ),
        );
        // Very wide: updates get their own column; comments stay
        // with the reviews.
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
                  weather,
                  const Divider(),
                  reviewsSection,
                  if (!threePane) ...[const Divider(), timeline],
                  const Divider(),
                  commentsSection,
                ],
              ),
            ),
            if (threePane) ...[
              const VerticalDivider(width: 1),
              SizedBox(
                width: (width * 0.28).clamp(360.0, 480.0),
                child: ListView(
                  padding: EdgeInsets.only(top: barBottom, bottom: 24),
                  children: [timeline],
                ),
              ),
            ],
          ],
        );
      },
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
        GlassAppBar.contentTop(context),
        sideGutter(c.maxWidth),
        24,
      ),
      children: children,
    ),
  );
}
