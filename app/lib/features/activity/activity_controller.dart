import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paging.dart';
import '../auth/auth_controller.dart';
import 'activity_models.dart';
import 'activity_repository.dart';

/// How many activity items the logged-in user has not seen (0 when logged
/// out). Loads on login; [UnreadActivity.refresh] asks again, e.g. when the
/// app comes back to the foreground or the profile tab is shown.
final unreadActivityProvider = NotifierProvider<UnreadActivity, int>(
  UnreadActivity.new,
);

class UnreadActivity extends Notifier<int> {
  int _gen = 0;

  ActivityRepository get _repo => ref.read(activityRepositoryProvider);

  @override
  int build() {
    final id = ref.watch(authControllerProvider.select((a) => a.value?.id));
    _gen++;
    if (id != null) {
      Future.microtask(() {
        if (ref.mounted) refresh();
      });
    }
    return 0;
  }

  /// Asks the server again. A failure keeps the count shown.
  Future<void> refresh() async {
    if (ref.read(authControllerProvider).value == null) {
      _gen++;
      state = 0;
      return;
    }
    final gen = ++_gen;
    try {
      final n = await _repo.unreadCount();
      if (ref.mounted && gen == _gen) state = n;
    } catch (_) {
      // offline or logged out meanwhile: keep what is shown
    }
  }

  /// Sets the count without asking, e.g. after marking items read.
  void set(int n) {
    _gen++;
    state = n < 0 ? 0 : n;
  }
}

/// The activity page's list, newest first. Loading it marks what it shows
/// as read; the items keep their unread highlight until the page is left.
final activityFeedProvider =
    NotifierProvider.autoDispose<ActivityFeedController, Paged<ActivityItem>>(
      ActivityFeedController.new,
    );

class ActivityFeedController extends Notifier<Paged<ActivityItem>>
    with CursorPaging<Paged<ActivityItem>, ActivityItem> {
  ActivityRepository get _repo => ref.read(activityRepositoryProvider);

  @override
  Paged<ActivityItem> build() {
    Future.microtask(() {
      if (ref.mounted) load();
    });
    return const Paged(loading: true);
  }

  @override
  Paged<ActivityItem> get paged => ref.mounted ? state : const Paged();

  @override
  set paged(Paged<ActivityItem> value) {
    if (ref.mounted) state = value;
  }

  @override
  int idOf(ActivityItem item) => item.id;

  @override
  Future<CursorPage<ActivityItem>> fetchPage(String? cursor) =>
      _repo.list(cursor: cursor);

  /// Loads page one and marks everything up to its newest item as read.
  Future<void> load() async {
    await loadFirst();
    await _markSeen();
  }

  /// Pull to refresh: the same, keeping the old list until the new one is in.
  Future<void> refresh() async {
    await loadFirst(keepItems: true);
    await _markSeen();
  }

  Future<void> _markSeen() async {
    if (!ref.mounted || paged.error != null) return;
    final items = paged.items;
    final unread = ref.read(unreadActivityProvider.notifier);
    // the badge clears at once; the server's answer corrects it
    unread.set(0);
    try {
      final left = await _repo.markRead(
        upTo: items.isEmpty ? null : items.first.id,
      );
      unread.set(left);
    } catch (_) {
      await unread.refresh();
    }
  }
}
