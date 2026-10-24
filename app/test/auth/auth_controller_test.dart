import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepository {
  ApiException? failWith;
  int registerCalls = 0;
  final user = const User(id: 1, email: 'a@b.ch', displayName: 'Alex');

  @override
  Future<AuthSession> login(String email, String password) async {
    if (failWith != null) throw failWith!;
    return AuthSession(
      user: user,
      tokens: const Tokens(accessToken: 'acc', refreshToken: 'ref'),
    );
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required bool adult,
  }) async {
    registerCalls++;
    return login(email, password);
  }

  @override
  Future<User?> me() async => user;

  String? changedCurrent;
  String? changedNext;
  String? deletedWith;

  @override
  Future<AuthSession> changePassword({
    required String current,
    required String next,
  }) async {
    if (failWith != null) throw failWith!;
    changedCurrent = current;
    changedNext = next;
    return AuthSession(
      user: user,
      tokens: const Tokens(accessToken: 'acc2', refreshToken: 'ref2'),
    );
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    if (failWith != null) throw failWith!;
    deletedWith = password;
  }
}

void main() {
  late FakeAuthRepository repo;
  late TokenStore store;
  late ProviderContainer container;

  setUp(() {
    repo = FakeAuthRepository();
    store = TokenStore.memory();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repo),
        tokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
  });

  test('login stores tokens and exposes user', () async {
    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).login('a@b.ch', 'pw');

    expect(container.read(authControllerProvider).value, repo.user);
    final t = await store.read();
    expect(t?.accessToken, 'acc');
    expect(t?.refreshToken, 'ref');
  });

  test('failed login surfaces error code', () async {
    repo.failWith = ApiException(401, 'invalid_credentials', 'nope');
    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).login('a@b.ch', 'x');

    final err = container.read(authControllerProvider).error;
    expect(err, isA<ApiException>());
    expect((err as ApiException).code, 'invalid_credentials');
    expect(await store.read(), isNull);
  });

  test('register is blocked until the 18+ box is ticked', () async {
    await container.read(authControllerProvider.future);
    final c = container.read(authControllerProvider.notifier);
    await c.register(
      email: 'a@b.ch',
      password: 'longenough1',
      displayName: 'A',
      adult: false,
    );

    expect(repo.registerCalls, 0);
    expect(
      (container.read(authControllerProvider).error as ApiException).code,
      'adult_required',
    );

    await c.register(
      email: 'a@b.ch',
      password: 'longenough1',
      displayName: 'A',
      adult: true,
    );
    expect(repo.registerCalls, 1);
    expect(container.read(authControllerProvider).value, repo.user);
  });

  test('logout clears tokens and user', () async {
    await container.read(authControllerProvider.future);
    final c = container.read(authControllerProvider.notifier);
    await c.login('a@b.ch', 'pw');
    await c.logout();
    expect(container.read(authControllerProvider).value, isNull);
    expect(await store.read(), isNull);
  });

  test('changePassword stores the new tokens and keeps the user', () async {
    await container.read(authControllerProvider.future);
    final c = container.read(authControllerProvider.notifier);
    await c.login('a@b.ch', 'pw');
    await c.changePassword(current: 'old', next: 'newpassword1');

    expect(repo.changedCurrent, 'old');
    expect(repo.changedNext, 'newpassword1');
    expect(container.read(authControllerProvider).value, repo.user);
    final t = await store.read();
    expect(t?.accessToken, 'acc2');
    expect(t?.refreshToken, 'ref2');
  });

  test(
    'changePassword with wrong password throws and stays signed in',
    () async {
      await container.read(authControllerProvider.future);
      final c = container.read(authControllerProvider.notifier);
      await c.login('a@b.ch', 'pw');
      repo.failWith = ApiException(403, 'wrong_password', 'nope');

      await expectLater(
        c.changePassword(current: 'bad', next: 'newpassword1'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'wrong_password'),
        ),
      );
      expect(container.read(authControllerProvider).value, repo.user);
      expect((await store.read())?.accessToken, 'acc');
    },
  );

  test('deleteAccount clears tokens and user', () async {
    await container.read(authControllerProvider.future);
    final c = container.read(authControllerProvider.notifier);
    await c.login('a@b.ch', 'pw');
    await c.deleteAccount(password: 'pw');

    expect(repo.deletedWith, 'pw');
    expect(container.read(authControllerProvider).value, isNull);
    expect(await store.read(), isNull);
  });

  test('deleteAccount with wrong password throws and keeps session', () async {
    await container.read(authControllerProvider.future);
    final c = container.read(authControllerProvider.notifier);
    await c.login('a@b.ch', 'pw');
    repo.failWith = ApiException(403, 'wrong_password', 'nope');

    await expectLater(
      c.deleteAccount(password: 'bad'),
      throwsA(isA<ApiException>()),
    );
    expect(container.read(authControllerProvider).value, repo.user);
    expect(await store.read(), isNotNull);
  });
}
