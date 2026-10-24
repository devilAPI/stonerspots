import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

/// Persists the auth tokens. Uses secure storage by default; [TokenStore.memory]
/// keeps them in memory (tests, or when no secure storage is available).
class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  TokenStore.memory() : _storage = null;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  final FlutterSecureStorage? _storage;
  Tokens? _memory;

  Future<Tokens?> read() async {
    final s = _storage;
    if (s == null) return _memory;
    try {
      final a = await s.read(key: _accessKey);
      final r = await s.read(key: _refreshKey);
      if (a == null || r == null) return null;
      return Tokens(accessToken: a, refreshToken: r);
    } catch (_) {
      return _memory;
    }
  }

  Future<void> write(Tokens tokens) async {
    _memory = tokens;
    final s = _storage;
    if (s == null) return;
    try {
      await s.write(key: _accessKey, value: tokens.accessToken);
      await s.write(key: _refreshKey, value: tokens.refreshToken);
    } catch (_) {
      // Secure storage unavailable: the in-memory copy is the fallback.
    }
  }

  Future<void> clear() async {
    _memory = null;
    final s = _storage;
    if (s == null) return;
    try {
      await s.delete(key: _accessKey);
      await s.delete(key: _refreshKey);
    } catch (_) {}
  }
}
