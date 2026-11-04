import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/paging.dart';
import '../../core/providers.dart' show apiClientProvider;
import 'activity_models.dart';

abstract class ActivityRepository {
  /// The caller's activity, newest first.
  Future<CursorPage<ActivityItem>> list({String? cursor});

  /// How many items the caller has not seen yet (`unread_activity` of
  /// `GET /me`).
  Future<int> unreadCount();

  /// Marks items up to [upTo] as read, all of them when null. Returns what
  /// is still unread.
  Future<int> markRead({int? upTo});
}

class ApiActivityRepository implements ActivityRepository {
  ApiActivityRepository(this._api);

  final ApiClient _api;

  @override
  Future<CursorPage<ActivityItem>> list({String? cursor}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/me/activity',
      query: {'limit': 30, 'cursor': ?cursor},
    );
    final page = CursorPage.fromJson(json, ActivityItem.fromJson);
    // kinds this app does not know yet are left out
    return CursorPage(
      page.items.whereType<ActivityItem>().toList(),
      page.nextCursor,
    );
  }

  @override
  Future<int> unreadCount() async {
    final me = await _api.get<Map<String, dynamic>>('/me');
    return (me['unread_activity'] ?? 0) as int;
  }

  @override
  Future<int> markRead({int? upTo}) async {
    final res = await _api.post<Map<String, dynamic>>(
      '/me/activity/read',
      data: {'up_to': ?upTo},
    );
    return (res['unread_activity'] ?? 0) as int;
  }
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ApiActivityRepository(ref.watch(apiClientProvider)),
);
