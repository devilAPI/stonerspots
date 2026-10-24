import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class ScriptedAdapter implements HttpClientAdapter {
  final List<RequestOptions> seen = [];
  final ResponseBody Function(RequestOptions) handler;
  ScriptedAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}

  int get refreshCalls =>
      seen.where((o) => o.path.endsWith('/auth/refresh')).length;
}

ResponseBody jsonBody(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

const unauthorized = {
  'error': {'code': 'unauthorized', 'message': 'x'},
};

void main() {
  test('401 triggers one refresh then retries', () async {
    final store = TokenStore.memory();
    await store.write(const Tokens(accessToken: 'old', refreshToken: 'r1'));
    final adapter = ScriptedAdapter((o) {
      if (o.path.endsWith('/auth/refresh')) {
        return jsonBody(200, {'access_token': 'new', 'refresh_token': 'r2'});
      }
      if (o.headers['Authorization'] == 'Bearer new') {
        return jsonBody(200, {'ok': true});
      }
      return jsonBody(401, unauthorized);
    });
    final client = ApiClient(
      tokenStore: store,
      baseUrl: 'http://x/api/v1',
      adapter: adapter,
    );

    final res = await client.get<Map<String, dynamic>>('/me');

    expect(res['ok'], true);
    expect(adapter.refreshCalls, 1);
    expect(adapter.seen.length, 3);
    expect((await store.read())?.refreshToken, 'r2');
  });

  test('failed refresh clears tokens and surfaces ApiException', () async {
    final store = TokenStore.memory();
    await store.write(const Tokens(accessToken: 'old', refreshToken: 'r1'));
    final adapter = ScriptedAdapter((o) => jsonBody(401, unauthorized));
    final client = ApiClient(
      tokenStore: store,
      baseUrl: 'http://x/api/v1',
      adapter: adapter,
    );

    await expectLater(
      client.get<Map<String, dynamic>>('/me'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'unauthorized'),
      ),
    );
    expect(await store.read(), isNull);
    expect(adapter.refreshCalls, 1);
  });

  test('error body is mapped to ApiException', () async {
    final adapter = ScriptedAdapter(
      (o) => jsonBody(409, {
        'error': {'code': 'possible_duplicate', 'message': 'dup'},
      }),
    );
    final client = ApiClient(
      tokenStore: TokenStore.memory(),
      baseUrl: 'http://x/api/v1',
      adapter: adapter,
    );
    await expectLater(
      client.post<Map<String, dynamic>>('/spots', data: {}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.code, 'code', 'possible_duplicate'),
      ),
    );
  });
}
