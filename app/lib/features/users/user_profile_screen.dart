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
import '../auth/auth_controller.dart';
import '../feed/feed_card.dart';
import '../feed/satellite_thumb.dart';
import '../reviews/rating_widgets.dart';
import 'author_link.dart';
import 'avatar_editor.dart';
import 'users_controller.dart';
import 'users_repository.dart';

enum _Tab { spots, updates }

/// A user's public profile: name, join date, counts, follow button and their
/// spots and updates. The profile tab shows the same page for the logged-in
/// user, with [asTab] set and its own buttons in [actions] and [headerExtra].
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.userId,
    this.asTab = false,
    this.actions = const [],
    this.headerExtra,
  });

  final int userId;

  /// Shown as a tab: no back button.
  final bool asTab;

  /// App bar buttons.
  final List<Widget> actions;

  /// Below the counts, in place of the follow button on your own profile.
  final Widget? headerExtra;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  final _scroll = ScrollController();
  var _tab = _Tab.spots;
  var _busy = false;

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
    if (!_scroll.hasClients || _scroll.position.extentAfter >= 400) return;
    switch (_tab) {
      case _Tab.spots:
        ref.read(userSpotsProvider(widget.userId).notifier).loadMore();
      case _Tab.updates:
        ref.read(userUpdatesProvider(widget.userId).notifier).loadMore();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(userProfileProvider(widget.userId));
    await switch (_tab) {
      _Tab.spots =>
        ref.read(userSpotsProvider(widget.userId).notifier).refresh(),
      _Tab.updates =>
        ref.read(userUpdatesProvider(widget.userId).notifier).refresh(),
    };
  }

  Future<void> _toggleFollow(UserProfile p) async {
    if (ref.read(authControllerProvider).value == null) {
      // pushed: after logging in it pops back to this profile
      context.push('/login');
      return;
    }
    final failed = AppLocalizations.of(context).errorGeneric;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(userProfileProvider(widget.userId).notifier)
          .setFollowing(!p.following);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final profile = ref.watch(userProfileProvider(widget.userId));
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        leading: widget.asTab ? null : const BackOrHomeButton(),
        title: Text(profile.value?.displayName ?? ''),
        actions: widget.actions,
      ),
      body: ProfileScope(
        userId: widget.userId,
        child: LayoutBuilder(
          builder: (context, c) => _body(context, l, profile, c.maxWidth),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l,
    AsyncValue<UserProfile> profile,
    double width,
  ) {
    final p = profile.value;
    if (p == null) {
      final error = profile.error;
      if (error == null) {
        return const _Centered(children: [CircularProgressIndicator()]);
      }
      final gone = error is ApiException && error.status == 404;
      return _Centered(
        key: const Key('userError'),
        children: [
          Text(gone ? l.userGone : l.errorGeneric),
          if (!gone)
            TextButton(
              onPressed: () =>
                  ref.invalidate(userProfileProvider(widget.userId)),
              child: Text(l.retry),
            ),
        ],
      );
    }
    final myId = ref.watch(authControllerProvider.select((a) => a.value?.id));
    // Both lists stay loaded, so switching between them is instant.
    final spots = ref.watch(userSpotsProvider(widget.userId));
    final updates = ref.watch(userUpdatesProvider(widget.userId));
    final insets = MediaQuery.paddingOf(context);
    final gutter = sideGutter(width);
    // A short first page may not fill the window, so nothing would scroll
    // to trigger the next one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onScroll();
    });
    return RefreshIndicator(
      edgeOffset: GlassAppBar.contentTop(context),
      onRefresh: _refresh,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          insets.left + gutter,
          GlassAppBar.contentTop(context),
          insets.right + gutter,
          insets.bottom + 16,
        ),
        children: [
          _Header(
            profile: p,
            busy: _busy,
            onFollow: () => _toggleFollow(p),
            editable: p.isMe && myId == p.id,
            extra: widget.headerExtra,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<_Tab>(
              key: const Key('userTabs'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _Tab.spots,
                  label: Text(l.userTabSpots),
                  icon: const Icon(Icons.place_outlined),
                ),
                ButtonSegment(
                  value: _Tab.updates,
                  label: Text(l.userTabUpdates),
                  icon: const Icon(Icons.dynamic_feed_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          ...switch (_tab) {
            _Tab.spots => _list(
              l,
              spots,
              empty: l.userNoSpots,
              retry: () => ref
                  .read(userSpotsProvider(widget.userId).notifier)
                  .loadFirst(),
              item: (s) => _SpotRow(key: ValueKey('s${s.id}'), spot: s),
            ),
            _Tab.updates => _list(
              l,
              updates,
              empty: l.userNoUpdates,
              retry: () => ref
                  .read(userUpdatesProvider(widget.userId).notifier)
                  .loadFirst(),
              item: (u) => FeedCard(
                key: ValueKey('u${u.id}'),
                item: u,
                // like the feed: a 4:3 picture on top would be taller than
                // a landscape phone
                layout: context.isPhoneLandscape
                    ? FeedCardLayout.side
                    : FeedCardLayout.stacked,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          },
        ],
      ),
    );
  }

  List<Widget> _list<T>(
    AppLocalizations l,
    Paged<T> page, {
    required String empty,
    required VoidCallback retry,
    required Widget Function(T) item,
  }) {
    if (page.error != null && page.items.isEmpty) {
      return [
        _Note(
          children: [
            Text(l.errorGeneric),
            TextButton(onPressed: retry, child: Text(l.retry)),
          ],
        ),
      ];
    }
    if (page.items.isEmpty && !page.loadedOnce) {
      return const [
        _Note(children: [CircularProgressIndicator()]),
      ];
    }
    if (page.items.isEmpty) {
      return [
        _Note(
          key: const Key('userListEmpty'),
          children: [Text(empty, textAlign: TextAlign.center)],
        ),
      ];
    }
    return [
      for (final i in page.items) item(i),
      if (page.loadingMore)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.busy,
    required this.onFollow,
    required this.editable,
    this.extra,
  });

  final UserProfile profile;
  final bool busy;
  final VoidCallback onFollow;
  final Widget? extra;

  /// Your own profile: tapping the picture changes it.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = profile;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (editable)
                OwnAvatarEditor(
                  userId: p.id,
                  name: p.displayName,
                  url: p.avatarUrl,
                )
              else
                AuthorAvatar(
                  author: Author(
                    id: p.id,
                    displayName: p.displayName,
                    avatarUrl: p.avatarUrl,
                  ),
                  radius: 28,
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName,
                      key: const Key('userName'),
                      style: theme.textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.userJoined(p.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(
                key: const Key('statSpots'),
                value: p.spotCount,
                label: l.userStatSpots,
              ),
              _Stat(
                key: const Key('statUpdates'),
                value: p.updateCount,
                label: l.userStatUpdates,
              ),
              _Stat(
                key: const Key('statFollowers'),
                value: p.followerCount,
                label: l.userStatFollowers,
              ),
              _Stat(
                key: const Key('statFollowing'),
                value: p.followingCount,
                label: l.userStatFollowing,
              ),
            ],
          ),
          if (!p.isMe) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: p.following
                  ? OutlinedButton.icon(
                      key: const Key('unfollowButton'),
                      onPressed: busy ? null : onFollow,
                      icon: const Icon(Icons.person_remove_outlined),
                      label: Text(l.userUnfollow),
                    )
                  : FilledButton.icon(
                      key: const Key('followButton'),
                      onPressed: busy ? null : onFollow,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(l.userFollow),
                    ),
            ),
          ],
          if (extra != null) ...[const SizedBox(height: 16), extra!],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.titleMedium),
          Text(
            label,
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

/// A message or spinner in place of a tab's list.
class _Note extends StatelessWidget {
  const _Note({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
    child: Column(children: children),
  );
}

class _SpotRow extends StatelessWidget {
  const _SpotRow({super.key, required this.spot});

  final Spot spot;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final cover = spot.coverUrl;
    return ListTile(
      key: Key('userSpot-${spot.id}'),
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
      onTap: () => context.push('/spot/${spot.id}'),
    );
  }
}
