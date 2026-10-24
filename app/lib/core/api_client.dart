import 'package:dio/dio.dart';

import 'token_store.dart';

const String kApiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8080/api/v1',
);

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

class ApiClient {
  ApiClient({
    required this.tokenStore,
    String? baseUrl,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
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
  Future<bool>? _refreshing;

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>('GET', path, query: query);

  Future<T> post<T>(
    String path, {
    Object? data,
    void Function(int sent, int total)? onSendProgress,
  }) => _send<T>('POST', path, data: data, onSendProgress: onSendProgress);

  Future<T> put<T>(String path, {Object? data}) =>
      _send<T>('PUT', path, data: data);

  Future<T> delete<T>(String path, {Map<String, dynamic>? query}) =>
      _send<T>('DELETE', path, query: query);

  Future<T> _send<T>(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    void Function(int, int)? onSendProgress,
  }) async {
    Future<Response<dynamic>> attempt() async {
      final tokens = await tokenStore.read();
      return _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        onSendProgress: onSendProgress,
        options: Options(
          method: method,
          headers: {
            if (tokens != null) 'Authorization': 'Bearer ${tokens.accessToken}',
          },
        ),
      );
    }

    try {
      try {
        return (await attempt()).data as T;
      } on DioException catch (e) {
        final isAuthPath = path.startsWith('/auth/');
        if (e.response?.statusCode == 401 && !isAuthPath && await _refresh()) {
          return (await attempt()).data as T;
        }
        rethrow;
      }
    } on DioException catch (e) {
      throw _toException(e);
    }
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
