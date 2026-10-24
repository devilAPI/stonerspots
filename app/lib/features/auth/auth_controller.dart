import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import 'auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(ref.watch(apiClientProvider)),
);

final authControllerProvider = AsyncNotifierProvider<AuthController, User?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final tokens = await ref.read(tokenStoreProvider).read();
    if (tokens == null) return null;
    try {
      return await ref.read(authRepositoryProvider).me();
    } catch (_) {
      return null;
    }
  }

  Future<void> login(String email, String password) => _authenticate(
    () => ref.read(authRepositoryProvider).login(email.trim(), password),
  );

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required bool adult,
  }) {
    if (!adult) {
      state = AsyncError(
        ApiException(400, 'adult_required', '18+ confirmation required'),
        StackTrace.current,
      );
      return Future.value();
    }
    return _authenticate(
      () => ref
          .read(authRepositoryProvider)
          .register(
            email: email.trim(),
            password: password,
            displayName: displayName.trim(),
            adult: adult,
          ),
    );
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(null);
  }

  Future<void> _authenticate(Future<AuthSession> Function() action) async {
    state = const AsyncLoading<User?>();
    try {
      final session = await action();
      await ref.read(tokenStoreProvider).write(session.tokens);
      state = AsyncData(session.user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }
}
