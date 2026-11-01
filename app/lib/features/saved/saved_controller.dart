import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/paging.dart';
import '../auth/auth_controller.dart';
import 'saved_repository.dart';

/// Riverpod would retry failed loads for a while, keeping pages spinning and
/// a tap on the bookmark waiting; these pages offer a retry themselves.
Duration? _noRetry(int _, Object _) => null;

int? _userId(Ref ref) =>
    ref.watch(authControllerProvider.select((a) => a.value?.id));

/// The user's lists; empty when logged out.
final savedListsProvider = FutureProvider.autoDispose<List<SpotList>>((ref) {
  if (_userId(ref) == null) return const <SpotList>[];
  return ref.watch(savedRepositoryProvider).lists();
}, retry: _noRetry);

final savedListProvider = FutureProvider.autoDispose.family<SpotList, int>(
  (ref, id) => ref.watch(savedRepositoryProvider).getList(id),
  retry: _noRetry,
);

/// Which of the user's lists hold a spot.
final spotSavedProvider = AsyncNotifierProvider.autoDispose
    .family<SpotSavedController, Set<int>, int>(
      SpotSavedController.new,
      retry: _noRetry,
    );

/// Reloads what shows the lists' contents after a spot changed lists.
void _listsChanged(Ref ref) {
  ref.invalidate(savedListsProvider);
  ref.invalidate(savedListSpotsProvider);
}

class SpotSavedController extends AsyncNotifier<Set<int>> {
  SpotSavedController(this.spotId);

  final int spotId;
  int _latest = 0;

  SavedRepository get _repo => ref.read(savedRepositoryProvider);

  @override
  Future<Set<int>> build() async {
    if (_userId(ref) == null) return const {};
    return _repo.membership(spotId);
  }

  /// Takes what the server answered to the newest write; answers to older
  /// writes could undo a later change.
  void _settle(int request, Set<int> ids) {
    if (!ref.mounted) return;
    if (request == _latest) state = AsyncData(ids);
    _listsChanged(ref);
  }

  Future<void> saveToFavourites() async {
    final request = ++_latest;
    _settle(request, await _repo.saveToFavourites(spotId));
  }

  /// Shows the change at once, so the checkboxes keep up with taps. Throws
  /// when it failed, with the change undone.
  Future<void> setInList(int listId, {required bool saved}) async {
    final request = ++_latest;
    void show({required bool inList}) {
      final ids = {...?state.value};
      inList ? ids.add(listId) : ids.remove(listId);
      state = AsyncData(ids);
    }

    show(inList: saved);
    try {
      _settle(
        request,
        saved
            ? await _repo.addSpot(listId, spotId)
            : await _repo.removeSpot(listId, spotId),
      );
    } catch (_) {
      if (ref.mounted) show(inList: !saved);
      rethrow;
    }
  }
}

/// The spots of a list, loading as soon as it is first watched.
final savedListSpotsProvider = NotifierProvider.autoDispose
    .family<SavedListSpotsController, Paged<Spot>, int>(
      SavedListSpotsController.new,
    );

class SavedListSpotsController extends Notifier<Paged<Spot>>
    with CursorPaging<Paged<Spot>, Spot> {
  SavedListSpotsController(this.listId);

  final int listId;

  SavedRepository get _repo => ref.read(savedRepositoryProvider);

  @override
  Paged<Spot> build() {
    Future.microtask(() {
      if (ref.mounted) loadFirst();
    });
    return const Paged(loading: true);
  }

  @override
  Paged<Spot> get paged => ref.mounted ? state : const Paged();

  @override
  set paged(Paged<Spot> value) {
    if (ref.mounted) state = value;
  }

  @override
  Future<CursorPage<Spot>> fetchPage(String? cursor) =>
      _repo.spots(listId, cursor: cursor);

  @override
  int idOf(Spot item) => item.id;

  Future<void> refresh() => loadFirst(keepItems: true);

  /// Takes the spot off the page at once; it comes back if that failed.
  Future<void> remove(Spot spot) async {
    final before = paged.items;
    paged = paged.copyWith(items: [...before.where((s) => s.id != spot.id)]);
    try {
      await _repo.removeSpot(listId, spot.id);
    } catch (_) {
      paged = paged.copyWith(items: before);
      rethrow;
    }
    if (!ref.mounted) return;
    ref.invalidate(savedListsProvider);
    ref.invalidate(spotSavedProvider(spot.id));
  }
}
