import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/users/users_repository.dart';
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

ApiClient _client(_Adapter a) => ApiClient(
  tokenStore: TokenStore.memory(),
  baseUrl: 'http://x/api/v1',
  adapter: a,
);

const _profile = {
  'id': 7,
  'display_name': 'Alice',
  'created_at': '2025-03-15T10:00:00Z',
  'spot_count': 2,
  'update_count': 3,
  'follower_count': 4,
  'following_count': 5,
  'following': true,
  'is_me': false,
};

const _update = {
  'id': 11,
  'body': 'hi',
  'photos': [],
  'created_at': '2026-01-01T10:00:00Z',
  'tag': 'note',
  'edited_at': null,
  'author': {'id': 7, 'display_name': 'Alice'},
  'spot': {'id': 3, 'title': 'S', 'lat': 48.0, 'lon': 11.0, 'tags': []},
  'update_count': 1,
};

void main() {
  test('profile parses every field', () {
    final p = UserProfile.fromJson(_profile);
    expect(p.id, 7);
    expect(p.displayName, 'Alice');
    expect(p.createdAt, DateTime.utc(2025, 3, 15, 10));
    expect(
      [p.spotCount, p.updateCount, p.followerCount, p.followingCount],
      [2, 3, 4, 5],
    );
    expect(p.following, isTrue);
    expect(p.isMe, isFalse);
  });

  test('withFollowing moves the follower count once', () {
    final p = UserProfile.fromJson(_profile); // following, 4 followers
    expect(p.withFollowing(true), same(p));
    final off = p.withFollowing(false);
    expect(off.following, isFalse);
    expect(off.followerCount, 3);
    expect(off.withFollowing(true).followerCount, 4);
  });

  test('requests: profile, pages with cursor, follow and unfollow', () async {
    final a = _Adapter((o) {
      if (o.method != 'GET') return ResponseBody.fromString('', 204);
      return switch (o.path) {
        '/users/7' => _json(200, _profile),
        '/users/7/spots' => _json(200, {
          'items': [
            {'id': 3, 'title': 'S', 'lat': 48.0, 'lon': 11.0, 'tags': []},
          ],
          'next_cursor': 'c2',
        }),
        _ => _json(200, {
          'items': [_update],
          'next_cursor': null,
        }),
      };
    });
    final repo = ApiUsersRepository(_client(a));

    expect((await repo.profile(7)).displayName, 'Alice');
    expect(a.seen.last.path, '/users/7');

    final spots = await repo.spots(7, cursor: 'c1');
    expect(a.seen.last.queryParameters, {'limit': 20, 'cursor': 'c1'});
    expect(spots.items.single.id, 3);
    expect(spots.nextCursor, 'c2');

    final updates = await repo.updates(7);
    expect(a.seen.last.path, '/users/7/updates');
    expect(a.seen.last.queryParameters, {'limit': 20});
    expect(updates.items.single.author.id, 7);
    expect(updates.nextCursor, isNull);

    await repo.follow(7);
    expect(a.seen.last.method, 'PUT');
    expect(a.seen.last.path, '/users/7/follow');
    await repo.unfollow(7);
    expect(a.seen.last.method, 'DELETE');
    expect(a.seen.last.path, '/users/7/follow');
  });

  test('the feed sends following only when set', () async {
    final a = _Adapter((_) => _json(200, {'items': [], 'next_cursor': null}));
    final feed = ApiFeedRepository(_client(a));
    await feed.fetch(sort: FeedSort.newest);
    expect(a.seen.last.queryParameters.containsKey('following'), isFalse);
    await feed.fetch(sort: FeedSort.newest, following: true);
    expect(a.seen.last.queryParameters['following'], true);
  });
}
