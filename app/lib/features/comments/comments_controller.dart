import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/paging.dart';
import 'comment_models.dart';
import 'comments_repository.dart';

/// The comments of one spot (by id), newest first, while its page is on
/// screen.
final spotCommentsProvider = NotifierProvider.autoDispose
    .family<SpotCommentsController, Paged<Comment>, int>(
      SpotCommentsController.new,
    );

class SpotCommentsController extends Notifier<Paged<Comment>>
    with CursorPaging<Paged<Comment>, Comment> {
  SpotCommentsController(this.spotId);

  final int spotId;

  CommentsRepository get _repo => ref.read(commentsRepositoryProvider);

  @override
  Paged<Comment> build() => const Paged();

  @override
  Paged<Comment> get paged => state;

  @override
  set paged(Paged<Comment> value) => state = value;

  @override
  int idOf(Comment item) => item.id;

  @override
  Future<CursorPage<Comment>> fetchPage(String? cursor) =>
      _repo.list(spotId, cursor: cursor);

  Future<void> load() => loadFirst();

  /// Posts [body] and shows it on top, as the newest. Errors propagate.
  Future<Comment> post(String body) async {
    final c = await _repo.create(spotId, body);
    if (!state.items.any((x) => x.id == c.id)) {
      state = state.copyWith(items: [c, ...state.items]);
    }
    return c;
  }

  /// Deletes the comment; one that is gone already counts as deleted.
  Future<void> delete(Comment c) async {
    try {
      await _repo.delete(c.id);
    } on ApiException catch (e) {
      if (e.status != 404) rethrow;
    }
    state = state.copyWith(
      items: state.items.where((x) => x.id != c.id).toList(),
    );
  }
}
