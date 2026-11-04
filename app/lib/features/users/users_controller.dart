import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/paging.dart';
import '../auth/auth_controller.dart';
import '../feed/feed_controller.dart';
import 'users_repository.dart';

/// The profile page offers a retry itself; Riverpod's would keep it spinning.
Duration? _noRetry(int _, Object _) => null;

/// A user's public profile. Reloads when someone else logs in, since
/// `following` and `is_me` depend on who is looking.
final userProfileProvider = AsyncNotifierProvider.autoDispose
    .family<UserProfileController, UserProfile, int>(
      UserProfileController.new,
      retry: _noRetry,
    );

class UserProfileController extends AsyncNotifier<UserProfile> {
  UserProfileController(this.userId);

  final int userId;
  int _latest = 0;

  UsersRepository get _repo => ref.read(usersRepositoryProvider);

  @override
  Future<UserProfile> build() {
    ref.watch(authControllerProvider.select((a) => a.value?.id));
    return _repo.profile(userId);
  }

  /// Shows the change at once; throws when it failed, with the change
  /// undone.
  Future<void> setFollowing(bool follow) async {
    final before = state.value;
    if (before == null) return;
    final request = ++_latest;
    state = AsyncData(before.withFollowing(follow));
    try {
      follow ? await _repo.follow(userId) : await _repo.unfollow(userId);
    } catch (_) {
      final now = state.value;
      if (ref.mounted && request == _latest && now != null) {
        state = AsyncData(now.withFollowing(!follow));
      }
      rethrow;
    }
    if (!ref.mounted) return;
    // A feed filtered to followed people now shows someone more or less.
    if (ref.read(feedControllerProvider).following) {
      ref.read(feedControllerProvider.notifier).refresh();
    }
  }
}

/// Paging over one user's list, loading as soon as it is first watched.
abstract class _UserPaged<T> extends Notifier<Paged<T>>
    with CursorPaging<Paged<T>, T> {
  _UserPaged(this.userId);

  final int userId;

  UsersRepository get repo => ref.read(usersRepositoryProvider);

  @override
  Paged<T> build() {
    Future.microtask(() {
      if (ref.mounted) loadFirst();
    });
    return Paged<T>(loading: true);
  }

  @override
  Paged<T> get paged => ref.mounted ? state : Paged<T>();

  @override
  set paged(Paged<T> value) {
    if (ref.mounted) state = value;
  }

  Future<void> refresh() => loadFirst(keepItems: true);
}

/// The spots a user added, newest first.
final userSpotsProvider = NotifierProvider.autoDispose
    .family<UserSpotsController, Paged<Spot>, int>(UserSpotsController.new);

class UserSpotsController extends _UserPaged<Spot> {
  UserSpotsController(super.userId);

  @override
  Future<CursorPage<Spot>> fetchPage(String? cursor) =>
      repo.spots(userId, cursor: cursor);

  @override
  int idOf(Spot item) => item.id;
}

/// The updates a user posted, newest first.
final userUpdatesProvider = NotifierProvider.autoDispose
    .family<UserUpdatesController, Paged<FeedItem>, int>(
      UserUpdatesController.new,
    );

class UserUpdatesController extends _UserPaged<FeedItem> {
  UserUpdatesController(super.userId);

  @override
  Future<CursorPage<FeedItem>> fetchPage(String? cursor) =>
      repo.updates(userId, cursor: cursor);

  @override
  int idOf(FeedItem item) => item.id;
}
