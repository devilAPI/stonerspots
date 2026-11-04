import 'package:dio/dio.dart';

import 'token_store.dart';

final String kApiUrl = normalizeApiUrl(
  const String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8080/api/v1',
  ),
);

/// Makes the configured API URL absolute: without a scheme the browser would
/// resolve it relative to the page (`stonerspots.example.com` becomes
/// `https://<pages>/stonerspots.example.com/...`). Adds `https://` when the
/// scheme is missing and `/api/v1` when no path is given.
String normalizeApiUrl(String raw) {
  var url = raw.trim();
  if (!url.contains('://')) url = 'https://$url';
  final uri = Uri.parse(url);
  var path = uri.path.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty) path = '/api/v1';
  return uri.replace(path: path).toString();
}

/// Error returned by the API: `{"error": {"code", "message"}}`.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, {this.details});

  final int status;
  final String code;
  final String message;

  /// The full decoded JSON error body, for endpoints that add fields next to
  /// `error` (e.g. `existing_id` on 409 `possible_duplicate`).
  final Map<String, dynamic>? details;

  @override
  String toString() => 'ApiException($status, $code, $message)';
}

/// Why [ApiClient] asks the admin for a 2FA code.
enum AdminCodeReason {
  /// An admin action needs a code and there is no admin session yet.
  required,

  /// The admin session ran out (or the server no longer accepts it).
  expired,

  /// The code just entered was wrong.
  invalid,

  /// The code just entered was used already; the next one is needed.
  reused,

  /// Too many wrong codes: nothing can be entered for a few minutes. The
  /// prompt only tells so; whatever it returns is ignored.
  rateLimited,
}

/// Asks the admin for the current 6-digit code; null when cancelled.
typedef AdminCodePrompt = Future<String?> Function(AdminCodeReason reason);

class _AdminSession {
  const _AdminSession(this.token, this.expiresAt);

  final String token;
  final DateTime expiresAt;
}

class ApiClient {
  ApiClient({
    required this.tokenStore,
    String? baseUrl,
    HttpClientAdapter? adapter,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl ?? kApiUrl,
           connectTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 30),
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final TokenStore tokenStore;
  final Dio _dio;
  final DateTime Function() _now;
  Future<bool>? _refreshing;

  // ---- admin 2FA (see backend/internal/auth/guard.go) ----
  //
  // An admin with 2FA proves it on every admin action. The client trades one
  // code for an admin session (POST /admin/2fa/session, about 15 minutes)
  // and sends it as X-Admin-Session on every request while it lasts. When
  // a request is refused for want of 2FA, it asks for a code through
  // [onAdminCodeNeeded], opens a session and sends the request once more.

  static const headerTotp = 'X-TOTP';
  static const headerAdminSession = 'X-Admin-Session';

  /// How long the server keeps an admin session (AdminSessionTTL).
  static const adminSessionTtl = Duration(minutes: 15);

  /// Codes asked for per refused request before giving up.
  static const maxAdminCodeAttempts = 3;

  /// A session this close to its end is not sent any more: it could run out
  /// on the way.
  static const _sessionMargin = Duration(seconds: 20);

  /// Asks the admin for a code. Without it, 2FA refusals are thrown as they
  /// are.
  AdminCodePrompt? onAdminCodeNeeded;

  /// Called when the server refuses an admin who has not set up 2FA yet
  /// (`totp_setup_required`, with `require_admin_totp`); the request still
  /// fails.
  void Function()? onAdminSetupRequired;

  _AdminSession? _adminSession;
  Future<bool>? _adminPrompt;

  /// The admin session token while it is valid.
  String? get _sessionToken {
    final s = _adminSession;
    if (s == null) return null;
    if (!_now().isBefore(s.expiresAt.subtract(_sessionMargin))) return null;
    return s.token;
  }

  bool get hasAdminSession => _sessionToken != null;

  /// Forgets the admin session (logout, another user).
  void clearAdminSession() => _adminSession = null;

  /// Trades [code] for an admin session, which is then sent with every
  /// request. Throws [ApiException] (403 `totp_invalid`, `totp_reused`,
  /// 429 `rate_limited`, ...).
  Future<void> openAdminSession(String code) async {
    final res = await _request(
      'POST',
      '/admin/2fa/session',
      // never with the old session: a session cannot make a new one
      sendSession: false,
      headers: {headerTotp: code.trim()},
    );
    final body = res.data as Map;
    final now = _now();
    final latest = now.add(adminSessionTtl);
    var expires = DateTime.tryParse('${body['expires_at']}');
    // Another clock than the server's could make it look over already or
    // far away; then count the server's TTL from now.
    if (expires == null || !expires.isAfter(now) || expires.isAfter(latest)) {
      expires = latest;
    }
    _adminSession = _AdminSession(body['token'] as String, expires);
  }

  /// [receiveTimeout] overrides the client's 30 s for slow endpoints.
  Future<T> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
  }) => _send<T>('GET', path, query: query, receiveTimeout: receiveTimeout);

  /// [receiveTimeout] overrides the client's 30 s for slow endpoints. On the
  /// web it bounds the whole request, upload included (dio sets the XHR
  /// timeout to connect + receive), so uploads need a long one.
  Future<T> post<T>(
    String path, {
    Object? data,
    void Function(int sent, int total)? onSendProgress,
    Duration? receiveTimeout,
  }) => _send<T>(
    'POST',
    path,
    data: data,
    onSendProgress: onSendProgress,
    receiveTimeout: receiveTimeout,
  );

  /// [onSendProgress] and [receiveTimeout] as for [post].
  Future<T> put<T>(
    String path, {
    Object? data,
    void Function(int sent, int total)? onSendProgress,
    Duration? receiveTimeout,
  }) => _send<T>(
    'PUT',
    path,
    data: data,
    onSendProgress: onSendProgress,
    receiveTimeout: receiveTimeout,
  );

  Future<T> patch<T>(String path, {Object? data}) =>
      _send<T>('PATCH', path, data: data);

  Future<T> delete<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>('DELETE', path, query: query);

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(int, int)? onSendProgress,
    Duration? receiveTimeout,
  }) async {
    Future<T> run() async =>
        (await _request(
              method,
              path,
              data: data,
              query: query,
              onSendProgress: onSendProgress,
              receiveTimeout: receiveTimeout,
            )).data
            as T;

    final sent = _sessionToken;
    try {
      return await run();
    } on ApiException catch (e) {
      if (!await _proveAdmin(e, sent)) rethrow;
    }
    return run();
  }

  /// One request with the auth headers; a 401 refreshes the tokens once and
  /// sends it again. Errors are thrown as [ApiException].
  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(int, int)? onSendProgress,
    Duration? receiveTimeout,
    Map<String, String> headers = const {},
    bool sendSession = true,
  }) async {
    Future<Response<dynamic>> attempt() async {
      final tokens = await tokenStore.read();
      final session = sendSession ? _sessionToken : null;
      final body = data;
      return _dio.request<dynamic>(
        path,
        // a multipart body can be sent only once; a retry needs a copy
        data: body is FormData && body.isFinalized ? body.clone() : body,
        queryParameters: query,
        onSendProgress: onSendProgress,
        options: Options(
          method: method,
          receiveTimeout: receiveTimeout,
          headers: {
            if (tokens != null) 'Authorization': 'Bearer ${tokens.accessToken}',
            headerAdminSession: ?session,
            ...headers,
          },
        ),
      );
    }

    try {
      try {
        return await attempt();
      } on DioException catch (e) {
        final isAuthPath = path.startsWith('/auth/');
        if (e.response?.statusCode == 401 && !isAuthPath && await _refresh()) {
          return await attempt();
        }
        rethrow;
      }
    } on DioException catch (e) {
      throw _toException(e);
    }
  }

  /// Handles a refusal for want of 2FA proof: true when an admin session is
  /// there now and the request should be sent again. [sent] is the session
  /// the request carried.
  Future<bool> _proveAdmin(ApiException e, String? sent) async {
    if (e.status != 403) return false;
    switch (e.code) {
      case 'totp_setup_required':
        onAdminSetupRequired?.call();
        return false;
      case 'totp_required' || 'totp_session_expired':
        break;
      default:
        return false;
    }
    final stale = sent != null || e.code == 'totp_session_expired';
    if (sent != null && _adminSession?.token == sent) _adminSession = null;
    // Another request may have opened a session in the meantime.
    final now = _sessionToken;
    if (now != null && now != sent) return true;
    // Requests refused at the same time share one prompt.
    return _adminPrompt ??= _askForSession(
      stale ? AdminCodeReason.expired : AdminCodeReason.required,
    ).whenComplete(() => _adminPrompt = null);
  }

  /// Asks for codes until one opens a session (true), the admin cancels
  /// (false) or gives up after [maxAdminCodeAttempts] wrong codes (throws
  /// the last error). Too many wrong codes (429) are shown, then thrown.
  Future<bool> _askForSession(AdminCodeReason reason) async {
    final ask = onAdminCodeNeeded;
    if (ask == null) return false;
    late ApiException last;
    for (var i = 0; i < maxAdminCodeAttempts; i++) {
      final code = await ask(reason);
      if (code == null || code.trim().isEmpty) return false;
      try {
        await openAdminSession(code);
        return true;
      } on ApiException catch (e) {
        switch (e.code) {
          case 'totp_invalid':
            reason = AdminCodeReason.invalid;
          case 'totp_reused':
            reason = AdminCodeReason.reused;
          case 'rate_limited':
            await ask(AdminCodeReason.rateLimited);
            rethrow;
          default:
            rethrow;
        }
        last = e;
      }
    }
    throw last;
  }

  /// Refreshes once; concurrent 401s share the same refresh call.
  Future<bool> _refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final tokens = await tokenStore.read();
    if (tokens == null) return false;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': tokens.refreshToken},
      );
      final body = res.data!;
      await tokenStore.write(
        Tokens(
          accessToken: body['access_token'] as String,
          refreshToken: body['refresh_token'] as String,
        ),
      );
      return true;
    } catch (_) {
      await tokenStore.clear();
      clearAdminSession();
      return false;
    }
  }

  ApiException _toException(DioException e) {
    final status = e.response?.statusCode ?? 0;
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        status,
        '${err['code'] ?? 'unknown'}',
        '${err['message'] ?? ''}',
        details: Map<String, dynamic>.from(data),
      );
    }
    return ApiException(status, 'network_error', e.message ?? '');
  }
}
