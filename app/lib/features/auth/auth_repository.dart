import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/token_store.dart';

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final User user;
  final Tokens tokens;
}

abstract class AuthRepository {
  Future<AuthSession> login(String email, String password);

  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required bool adult,
  });

  /// The current user, or null when not logged in.
  Future<User?> me();

  /// Changes the password; the server revokes other sessions and returns a
  /// fresh session for this device. Wrong current password: 403
  /// `wrong_password`.
  Future<AuthSession> changePassword({
    required String current,
    required String next,
  });

  /// Permanently deletes the account and its content. Wrong password: 403
  /// `wrong_password`.
  Future<void> deleteAccount({required String password});
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);

  final ApiClient _api;

  AuthSession _session(Map<String, dynamic> j) => AuthSession(
    user: User.fromJson(j['user'] as Map<String, dynamic>),
    tokens: Tokens(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
    ),
  );

  @override
  Future<AuthSession> login(String email, String password) async => _session(
    await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
    ),
  );

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String displayName,
    required bool adult,
  }) async => _session(
    await _api.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'display_name': displayName,
        'adult': adult,
      },
    ),
  );

  @override
  Future<User?> me() async {
    try {
      return User.fromJson(await _api.get<Map<String, dynamic>>('/me'));
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  @override
  Future<AuthSession> changePassword({
    required String current,
    required String next,
  }) async => _session(
    await _api.put<Map<String, dynamic>>(
      '/me/password',
      data: {'current_password': current, 'new_password': next},
    ),
  );

  @override
  Future<void> deleteAccount({required String password}) async {
    await _api.post<dynamic>('/me/delete', data: {'password': password});
  }
}
