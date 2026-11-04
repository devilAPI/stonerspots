import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';
import '../users/users_controller.dart';
import 'activity_controller.dart';

/// App bar button to the activity page, with the unread count as a badge.
/// Shows nothing when logged out.
class ActivityBell extends ConsumerWidget {
  const ActivityBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(
      authControllerProvider.select((a) => a.value != null),
    );
    if (!loggedIn) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final unread = ref.watch(unreadActivityProvider);
    return IconButton(
      key: const Key('open-activity'),
      tooltip: l10n.activityTooltip(unread),
      icon: Badge(
        key: const Key('activity-badge'),
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          unread > 0
              ? Icons.notifications_active_outlined
              : Icons.notifications_none,
        ),
      ),
      onPressed: () => context.push('/activity'),
    );
  }
}

/// Keeps the unread activity count fresh: asks again when the app returns
/// to the foreground and whenever [profileShown] turns true.
class ActivityRefresher extends ConsumerStatefulWidget {
  const ActivityRefresher({
    super.key,
    required this.profileShown,
    required this.child,
  });

  final bool profileShown;
  final Widget child;

  @override
  ConsumerState<ActivityRefresher> createState() => _ActivityRefresherState();
}

class _ActivityRefresherState extends ConsumerState<ActivityRefresher> {
  late final AppLifecycleListener _lifecycle;

  void _refresh() => ref.read(unreadActivityProvider.notifier).refresh();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void didUpdateWidget(ActivityRefresher old) {
    super.didUpdateWidget(old);
    if (widget.profileShown && !old.profileShown) {
      _refresh();
      _refreshOwnProfile();
    }
  }

  /// The profile tab stays alive between visits, so its counts and lists
  /// would miss what was posted meanwhile.
  void _refreshOwnProfile() {
    final me = ref.read(authControllerProvider).value?.id;
    if (me == null) return;
    if (ref.exists(userProfileProvider(me))) {
      ref.invalidate(userProfileProvider(me));
    }
    if (ref.exists(userSpotsProvider(me))) {
      ref.read(userSpotsProvider(me).notifier).refresh();
    }
    if (ref.exists(userUpdatesProvider(me))) {
      ref.read(userUpdatesProvider(me).notifier).refresh();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
