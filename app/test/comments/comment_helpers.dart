import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/comments/comment_models.dart';
import 'package:app/features/comments/comments_repository.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:flutter_test/flutter_test.dart';

Comment comment(
  int id, {
  String body = 'hi',
  bool mine = false,
  int authorId = 9,
  String name = 'Bo',
}) => Comment(
  id: id,
  updateId: 7,
  body: body,
  createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  author: Author(id: authorId, displayName: name),
  mine: mine,
);

FeedItem update({int id = 7, int comments = 0}) => FeedItem(
  id: id,
  body: 'hello',
  photos: const [],
  createdAt: DateTime(2026, 10, 1),
  author: const Author(id: 2, displayName: 'Ann'),
  spot: const Spot(id: 5, title: 'Lake bench', lat: 1, lon: 2),
  commentCount: comments,
);

/// Pages by cursor: `null` is the first page.
class FakeComments implements CommentsRepository {
  FakeComments(this.pages);

  final Map<String?, CursorPage<Comment>> pages;
  final calls = <String>[];
  Object? createError;
  Object? deleteError;
  int _nextId = 100;

  @override
  Future<CursorPage<Comment>> list(int updateId, {String? cursor}) async {
    calls.add('list:$updateId:${cursor ?? ''}');
    return pages[cursor] ?? const CursorPage([], null);
  }

  @override
  Future<Comment> create(int updateId, String body) async {
    calls.add('create:$updateId:$body');
    if (createError != null) throw createError!;
    return comment(_nextId++, body: body, mine: true, authorId: 1, name: 'Me');
  }

  @override
  Future<void> delete(int commentId) async {
    calls.add('delete:$commentId');
    if (deleteError != null) throw deleteError!;
  }
}

class FakeSpotApi extends Fake implements SpotApi {
  final reports = <String>[];

  @override
  Future<void> report(String targetType, int targetId, String reason) async {
    reports.add('$targetType:$targetId:$reason');
  }
}

ApiException apiError(int status, String code) =>
    ApiException(status, code, code);
