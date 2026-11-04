import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart' show FeedItem;
import '../../core/paging.dart';
import 'comment_models.dart';
import 'comments_repository.dart';

/// The comment thread of one update (by id), while it is on screen.
final commentThreadProvider = NotifierProvider.autoDispose
    .family<CommentThreadController, Paged<Comment>, int>(
      CommentThreadController.new,
    );

class CommentThreadController extends Notifier<Paged<Comment>>
    with CursorPaging<Paged<Comment>, Comment> {
  CommentThreadController(this.updateId);

  final int updateId;

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
      _repo.list(updateId, cursor: cursor);

  Future<void> load() => loadFirst();

  /// Newer pages may follow a comment posted here; ids keep the thread in
  /// order.
  @override
  Future<void> loadMore() async {
    await super.loadMore();
    final sorted = [...state.items]..sort((a, b) => a.id.compareTo(b.id));
    state = state.copyWith(items: sorted);
  }

  /// Posts [body] and shows it at the end of the thread. Errors propagate.
  Future<Comment> post(String body) async {
    final c = await _repo.create(updateId, body);
    if (!state.items.any((x) => x.id == c.id)) {
      state = state.copyWith(items: [...state.items, c]);
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

/// Comment counts changed in this session, per update id. [base] is the
/// count the update came with; when a reload brings a different one, that
/// newer server count wins.
typedef CommentCount = ({int base, int count});

final commentCountsProvider =
    NotifierProvider<CommentCounts, Map<int, CommentCount>>(CommentCounts.new);

class CommentCounts extends Notifier<Map<int, CommentCount>> {
  @override
  Map<int, CommentCount> build() => const {};

  /// What to show for [item]'s comment count.
  static int of(Map<int, CommentCount> counts, FeedItem item) {
    final c = counts[item.id];
    return c != null && c.base == item.commentCount
        ? c.count
        : item.commentCount;
  }

  /// Adds [delta] to the count shown for update [updateId], which came with
  /// [base] comments.
  void adjust(int updateId, int base, int delta) {
    final c = state[updateId];
    final shown = c != null && c.base == base ? c.count : base;
    final next = shown + delta;
    state = {...state, updateId: (base: base, count: next < 0 ? 0 : next)};
  }
}
