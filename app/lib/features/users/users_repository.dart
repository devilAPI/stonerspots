import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/providers.dart' show apiClientProvider;

/// The public profile of a user (`GET /users/{id}`).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.createdAt,
    this.spotCount = 0,
    this.updateCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.following = false,
    this.isMe = false,
  });

  final int id;
  final String displayName;
  final DateTime createdAt;
  final int spotCount;
  final int updateCount;
  final int followerCount;
  final int followingCount;

  /// The caller follows this user; false when logged out.
  final bool following;

  /// This is the caller's own profile.
  final bool isMe;

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id: j['id'] as int,
    displayName: (j['display_name'] ?? '') as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    spotCount: (j['spot_count'] ?? 0) as int,
    updateCount: (j['update_count'] ?? 0) as int,
    followerCount: (j['follower_count'] ?? 0) as int,
    followingCount: (j['following_count'] ?? 0) as int,
    following: (j['following'] ?? false) as bool,
    isMe: (j['is_me'] ?? false) as bool,
  );

  /// This profile after the caller followed ([follow]) or unfollowed it.
  UserProfile withFollowing(bool follow) => follow == following
      ? this
      : UserProfile(
          id: id,
          displayName: displayName,
          createdAt: createdAt,
          spotCount: spotCount,
          updateCount: updateCount,
          followerCount: followerCount + (follow ? 1 : -1),
          followingCount: followingCount,
          following: follow,
          isMe: isMe,
        );
}

abstract class UsersRepository {
  /// Throws [ApiException] 404 for unknown, banned or deleted users.
  Future<UserProfile> profile(int id);

  /// The user's spots, newest first.
  Future<CursorPage<Spot>> spots(int id, {String? cursor});

  /// The user's updates, newest first.
  Future<CursorPage<FeedItem>> updates(int id, {String? cursor});

  /// Both are idempotent; they need a login.
  Future<void> follow(int id);
  Future<void> unfollow(int id);
}

class ApiUsersRepository implements UsersRepository {
  ApiUsersRepository(this._api);

  final ApiClient _api;

  @override
  Future<UserProfile> profile(int id) async =>
      UserProfile.fromJson(await _api.get<Map<String, dynamic>>('/users/$id'));

  @override
  Future<CursorPage<Spot>> spots(int id, {String? cursor}) async =>
      CursorPage.fromJson(
        await _api.get<Map<String, dynamic>>(
          '/users/$id/spots',
          query: {'limit': 20, 'cursor': ?cursor},
        ),
        Spot.fromJson,
      );

  @override
  Future<CursorPage<FeedItem>> updates(int id, {String? cursor}) async =>
      CursorPage.fromJson(
        await _api.get<Map<String, dynamic>>(
          '/users/$id/updates',
          query: {'limit': 20, 'cursor': ?cursor},
        ),
        FeedItem.fromJson,
      );

  @override
  Future<void> follow(int id) async {
    await _api.put<dynamic>('/users/$id/follow');
  }

  @override
  Future<void> unfollow(int id) async {
    await _api.delete<dynamic>('/users/$id/follow');
  }
}

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => ApiUsersRepository(ref.watch(apiClientProvider)),
);
