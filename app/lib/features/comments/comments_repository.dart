import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/paging.dart';
import '../../core/providers.dart' show apiClientProvider;
import 'comment_models.dart';

abstract class CommentsRepository {
  /// One page of an update's comments, oldest first.
  Future<CursorPage<Comment>> list(int updateId, {String? cursor});

  /// Posts a comment as the current user.
  Future<Comment> create(int updateId, String body);

  /// Deletes a comment (own, or any as admin). 404 `not_found` is thrown as
  /// [ApiException]: it is gone already, or not the caller's to delete.
  Future<void> delete(int commentId);
}

class ApiCommentsRepository implements CommentsRepository {
  ApiCommentsRepository(this._api);

  final ApiClient _api;

  @override
  Future<CursorPage<Comment>> list(int updateId, {String? cursor}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/updates/$updateId/comments',
      query: {'limit': 20, 'cursor': ?cursor},
    );
    return CursorPage.fromJson(json, Comment.fromJson);
  }

  @override
  Future<Comment> create(int updateId, String body) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/updates/$updateId/comments',
      data: {'body': body},
    );
    return Comment.fromJson(json);
  }

  @override
  Future<void> delete(int commentId) =>
      _api.delete<dynamic>('/comments/$commentId');
}

final commentsRepositoryProvider = Provider<CommentsRepository>(
  (ref) => ApiCommentsRepository(ref.watch(apiClientProvider)),
);
