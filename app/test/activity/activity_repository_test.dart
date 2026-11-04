import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/activity/activity_models.dart';
import 'package:app/features/activity/activity_repository.dart';
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

ApiActivityRepository _repo(_Adapter a) => ApiActivityRepository(
  ApiClient(
    tokenStore: TokenStore.memory(),
    baseUrl: 'http://x/api/v1',
    adapter: a,
  ),
);

void main() {
  test('parses every kind and leaves out unknown ones', () async {
    final a = _Adapter(
      (_) => _json(200, {
        'items': [
          {
            'id': 9,
            'kind': 'comment',
            'created_at': '2026-11-04T10:00:00Z',
            'read': false,
            'actor': {'id': 3, 'display_name': 'Cleo'},
            'spot': {'id': 42, 'title': 'Bank'},
            'update_id': 5,
            'comment_id': 77,
            'comment_preview': 'Schön hier',
          },
          {
            'id': 8,
            'kind': 'poke',
            'created_at': '2026-11-04T09:00:00Z',
            'actor': {'id': 4, 'display_name': 'X'},
          },
          {
            'id': 7,
            'kind': 'follow',
            'created_at': '2026-11-03T09:00:00Z',
            'read': true,
            'actor': {'id': 4, 'display_name': 'Bob'},
            'spot': null,
            'update_id': null,
            'comment_preview': null,
          },
        ],
        'next_cursor': 'abc',
      }),
    );
    final page = await _repo(a).list(cursor: 'prev');
    expect(a.seen.single.path, endsWith('/me/activity'));
    expect(a.seen.single.queryParameters['cursor'], 'prev');
    expect(page.nextCursor, 'abc');
    expect(page.items.map((i) => i.id), [9, 7]);
    final c = page.items.first;
    expect(c.kind, ActivityKind.comment);
    expect(c.read, isFalse);
    expect(c.actor.displayName, 'Cleo');
    expect(c.spot!.title, 'Bank');
    expect(c.updateId, 5);
    expect(c.commentPreview, 'Schön hier');
    expect(c.target, '/spot/42');
    final f = page.items.last;
    expect(f.kind, ActivityKind.follow);
    expect(f.read, isTrue);
    expect(f.spot, isNull);
    expect(f.target, '/user/4');
  });

  test('unread count comes from /me', () async {
    final a = _Adapter(
      (_) => _json(200, {
        'id': 1,
        'email': 'a@b.de',
        'display_name': 'A',
        'unread_activity': 4,
      }),
    );
    expect(await _repo(a).unreadCount(), 4);
    expect(a.seen.single.path, endsWith('/me'));
  });

  test('marking read sends up_to, or nothing for all', () async {
    final a = _Adapter((_) => _json(200, {'unread_activity': 1}));
    final repo = _repo(a);
    expect(await repo.markRead(upTo: 12), 1);
    expect(await repo.markRead(), 1);
    expect(a.seen.map((o) => o.method), ['POST', 'POST']);
    expect(a.seen.first.path, endsWith('/me/activity/read'));
    expect(a.seen.first.data, {'up_to': 12});
    expect(a.seen.last.data, <String, dynamic>{});
  });
}
