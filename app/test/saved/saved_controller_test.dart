import 'dart:async';

import 'package:app/core/models.dart';
import 'package:app/core/paging.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/saved/saved_controller.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'saved_helpers.dart';

/// Lets the tests decide when a write answers.
class _HeldWrites extends FakeSaved {
  final held = <Completer<Set<int>>>[];

  Future<Set<int>> _hold() {
    final c = Completer<Set<int>>();
    held.add(c);
    return c.future;
  }

  @override
  Future<Set<int>> addSpot(int listId, int spotId) => _hold();

  @override
  Future<Set<int>> removeSpot(int listId, int spotId) => _hold();
}

class _LoggedOutThenIn extends AuthController {
  @override
  Future<User?> build() async => null;

  void logIn() => state = const AsyncData(kUser);
}

ProviderContainer _container(FakeSaved repo, {User? user = kUser}) {
  final c = ProviderContainer(
    overrides: [
      savedRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(() => FakeAuth(user)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _settled() => Future<void>.delayed(Duration.zero);

void main() {
  test('logged out nothing is asked of the server', () async {
    final repo = FakeSaved();
    final c = _container(repo, user: null);
    c.listen(authControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    final sub = c.listen(spotSavedProvider(5), (_, _) {});
    expect(await c.read(spotSavedProvider(5).future), isEmpty);
    expect(await c.read(savedListsProvider.future), isEmpty);
    sub.close();
    expect(repo.calls, isEmpty);
  });

  test('logging in loads what the spot is saved in', () async {
    final repo = FakeSaved(
      items: {
        kFavourites: {5},
      },
    );
    final auth = _LoggedOutThenIn();
    final c = ProviderContainer(
      overrides: [
        savedRepositoryProvider.overrideWithValue(repo),
        authControllerProvider.overrideWith(() => auth),
      ],
    );
    addTearDown(c.dispose);
    c.listen(spotSavedProvider(5), (_, _) {});
    await c.read(authControllerProvider.future);
    await _settled();
    expect(c.read(spotSavedProvider(5)).value, isEmpty);
    auth.logIn();
    await _settled();
    await _settled();
    expect(c.read(spotSavedProvider(5)).value, {kFavourites});
  });

  test('a failed load fails at once, without retrying', () async {
    final repo = _Failing();
    final c = _container(repo);
    c.listen(authControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    c.listen(spotSavedProvider(5), (_, _) {});
    await expectLater(c.read(spotSavedProvider(5).future), throwsException);
    expect(repo.tries, 1);
  });

  test('an open list follows a spot that changes lists', () async {
    final repo = FakeSaved(
      items: {
        2: {5},
      },
    );
    final c = _container(repo);
    c.listen(authControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    final seen = <Paged<Spot>>[];
    c.listen(savedListSpotsProvider(2), (_, next) => seen.add(next));
    c.listen(spotSavedProvider(5), (_, _) {});
    await _settled();
    await _settled();
    expect(c.read(savedListSpotsProvider(2)).items.map((s) => s.id), [5]);

    await c.read(spotSavedProvider(5).notifier).setInList(2, saved: false);
    await _settled();
    await _settled();
    expect(c.read(savedListSpotsProvider(2)).items, isEmpty);
    expect(c.read(savedListSpotsProvider(2)).loadedOnce, isTrue);
  });

  test('an older answer cannot undo a newer change', () async {
    final repo = _HeldWrites();
    final c = _container(repo);
    c.listen(authControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    c.listen(spotSavedProvider(5), (_, _) {});
    await c.read(spotSavedProvider(5).future);
    final ctrl = c.read(spotSavedProvider(5).notifier);

    final first = ctrl.setInList(2, saved: true);
    final second = ctrl.setInList(3, saved: true);
    expect(c.read(spotSavedProvider(5)).value, {2, 3});

    repo.held[1].complete({2, 3});
    await second;
    repo.held[0].complete({2}); // arrives late
    await first;
    expect(c.read(spotSavedProvider(5)).value, {2, 3});
  });

  test('a failed change undoes only itself', () async {
    final repo = _HeldWrites();
    final c = _container(repo);
    c.listen(authControllerProvider, (_, _) {});
    await c.read(authControllerProvider.future);
    c.listen(spotSavedProvider(5), (_, _) {});
    await c.read(spotSavedProvider(5).future);
    final ctrl = c.read(spotSavedProvider(5).notifier);

    final failing = ctrl.setInList(2, saved: true);
    final other = ctrl.setInList(3, saved: true);
    repo.held[0].completeError(Exception('down'));
    await expectLater(failing, throwsException);
    expect(c.read(spotSavedProvider(5)).value, {3});
    repo.held[1].complete({3});
    await other;
  });
}

class _Failing extends FakeSaved {
  int tries = 0;

  @override
  Future<Set<int>> membership(int spotId) async {
    tries++;
    throw Exception('down');
  }
}
