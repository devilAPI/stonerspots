import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/reviews/reviews_repository.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions) handler;
  final seen = <RequestOptions>[];

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
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody _empty(int status) => ResponseBody.fromString('', status);

ApiClient _client(_Adapter a) => ApiClient(
  tokenStore: TokenStore.memory(),
  baseUrl: 'http://x/api/v1',
  adapter: a,
);

void main() {
  test('post sends the tag, edit sends only given fields, delete', () async {
    final a = _Adapter(
      (o) => o.method == 'DELETE' ? _empty(204) : _json(200, {}),
    );
    final repo = ApiUpdatesRepository(_client(a));
    await repo.post(5, body: 'hi', photoIds: [1], tag: UpdateTag.stillGood);
    expect(a.seen.last.method, 'POST');
    expect(a.seen.last.path, '/spots/5/updates');
    expect(a.seen.last.data, {
      'body': 'hi',
      'photo_ids': [1],
      'tag': 'still_good',
    });
    await repo.edit(7, tag: UpdateTag.closed);
    expect(a.seen.last.method, 'PATCH');
    expect(a.seen.last.path, '/updates/7');
    expect(a.seen.last.data, {'tag': 'closed'});
    await repo.edit(7, body: 'x');
    expect(a.seen.last.data, {'body': 'x'});
    await repo.delete(7);
    expect(a.seen.last.method, 'DELETE');
    expect(a.seen.last.path, '/updates/7');
  });

  test('reviews: list query, save PUT, delete tolerates 404', () async {
    final a = _Adapter((o) {
      if (o.method == 'DELETE') {
        return _json(404, {
          'error': {'code': 'not_found', 'message': 'x'},
        });
      }
      if (o.method == 'PUT') {
        return _json(200, {
          'id': 1,
          'rating': 5,
          'body': 'b',
          'created_at': '2026-10-24T10:00:00Z',
          'updated_at': '2026-10-24T10:00:00Z',
          'author': {'id': 1, 'display_name': 'A'},
        });
      }
      return _json(200, {
        'summary': {'avg': 0, 'count': 0, 'distribution': {}},
        'mine': null,
        'items': [],
        'next_cursor': null,
      });
    });
    final repo = ApiReviewsRepository(_client(a));
    await repo.list(5, cursor: 'c');
    expect(a.seen.last.path, '/spots/5/reviews');
    expect(a.seen.last.queryParameters['cursor'], 'c');
    final saved = await repo.save(5, 5, 'b');
    expect(a.seen.last.path, '/spots/5/review');
    expect(a.seen.last.data, {'rating': 5, 'body': 'b'});
    expect(saved.rating, 5);
    await repo.delete(5); // 404 = already gone
    expect(a.seen.last.method, 'DELETE');
  });

  test('reviews: other delete errors propagate', () async {
    final a = _Adapter(
      (o) => _json(500, {
        'error': {'code': 'internal', 'message': 'x'},
      }),
    );
    expect(
      ApiReviewsRepository(_client(a)).delete(5),
      throwsA(isA<ApiException>()),
    );
  });
}
