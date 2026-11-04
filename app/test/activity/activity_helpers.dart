import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/activity/activity_models.dart';
import 'package:app/features/activity/activity_repository.dart';
import 'package:app/features/auth/auth_controller.dart';

const kMe = User(id: 1, email: 'me@x.de', displayName: 'Me');

class FakeAuth extends AuthController {
  FakeAuth(this.user);
  final User? user;
  @override
  Future<User?> build() async => user;
}

ActivityItem followBy(int id, {bool read = false}) => ActivityItem(
  id: id,
  kind: ActivityKind.follow,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  actor: const Author(id: 7, displayName: 'Alice'),
  read: read,
);

ActivityItem likeOf(int id, {bool read = false}) => ActivityItem(
  id: id,
  kind: ActivityKind.like,
  createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  actor: const Author(id: 8, displayName: 'Bob'),
  read: read,
  spot: const ActivitySpot(id: 42, title: 'Bank am See'),
);

/// A comment on the user's spot; [oldUpdateId] makes it one from when
/// comments hung under updates.
ActivityItem commentOn(int id, {bool read = false, int? oldUpdateId}) =>
    ActivityItem(
      id: id,
      kind: ActivityKind.comment,
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      actor: const Author(id: 9, displayName: 'Cleo'),
      read: read,
      spot: const ActivitySpot(id: 43, title: 'Aussicht'),
      updateId: oldUpdateId,
      commentPreview: 'Schöner Ort',
    );

ActivityItem reviewOf(int id, {bool read = false}) => ActivityItem(
  id: id,
  kind: ActivityKind.review,
  createdAt: DateTime.now().subtract(const Duration(days: 3)),
  actor: const Author(id: 10, displayName: 'Dana'),
  read: read,
  spot: const ActivitySpot(id: 44, title: 'Wald'),
);

/// In-memory activity, recording its calls. Pages of [pageSize]; cursors
/// are offsets. Marking read flips the stored items and the unread count.
class FakeActivity implements ActivityRepository {
  FakeActivity({List<ActivityItem>? items, int? unread})
    : items = items ?? [],
      unread = unread ?? (items ?? []).where((i) => !i.read).length;

  List<ActivityItem> items;
  int unread;
  int pageSize = 100;
  Object? fail;
  final calls = <String>[];

  @override
  Future<CursorPage<ActivityItem>> list({String? cursor}) async {
    calls.add('list:${cursor ?? ''}');
    if (fail != null) throw fail!;
    final start = int.tryParse(cursor ?? '') ?? 0;
    final end = (start + pageSize).clamp(0, items.length);
    return CursorPage(
      items.sublist(start, end),
      end < items.length ? '$end' : null,
    );
  }

  @override
  Future<int> unreadCount() async {
    calls.add('unread');
    if (fail != null) throw fail!;
    return unread;
  }

  @override
  Future<int> markRead({int? upTo}) async {
    calls.add('read:${upTo ?? 'all'}');
    if (fail != null) throw fail!;
    items = [
      for (final i in items)
        upTo == null || i.id <= upTo
            ? ActivityItem(
                id: i.id,
                kind: i.kind,
                createdAt: i.createdAt,
                actor: i.actor,
                read: true,
                spot: i.spot,
                updateId: i.updateId,
                commentPreview: i.commentPreview,
              )
            : i,
    ];
    unread = items.where((i) => !i.read).length;
    return unread;
  }
}
