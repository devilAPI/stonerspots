import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:app/l10n/app_localizations_de.dart';
import 'package:app/l10n/app_localizations_en.dart';
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

(ApiSavedRepository, _Adapter) _repo(
  ResponseBody Function(RequestOptions) handler,
) {
  final a = _Adapter(handler);
  return (
    ApiSavedRepository(
      ApiClient(
        tokenStore: TokenStore.memory(),
        baseUrl: 'http://x/api/v1',
        adapter: a,
      ),
    ),
    a,
  );
}

void main() {
  test('reads lists, with an empty cover as none', () async {
    final (repo, a) = _repo(
      (_) => _json(200, {
        'items': [
          {
            'id': 1,
            'name': 'Favourites',
            'is_default': true,
            'spot_count': 2,
            'cover_url': 'http://x/a.jpg',
          },
          {
            'id': 2,
            'name': 'Rainy days',
            'is_default': false,
            'spot_count': 0,
            'cover_url': '',
          },
        ],
      }),
    );
    final lists = await repo.lists();
    expect(a.seen.single.path, '/lists');
    expect(lists.first.isDefault, isTrue);
    expect(lists.first.spotCount, 2);
    expect(lists.first.coverUrl, 'http://x/a.jpg');
    expect(lists.last.coverUrl, isNull);
  });

  test('the default list is named by the flag, others by themselves', () {
    final en = AppLocalizationsEn();
    final de = AppLocalizationsDe();
    const fav = SpotList(id: 1, name: 'Favourites', isDefault: true);
    const own = SpotList(id: 2, name: 'Rainy days');
    expect(fav.title(de), 'Favoriten');
    expect(fav.title(en), 'Favourites');
    expect(own.title(de), 'Rainy days');
  });

  test('saves through the default alias and reads the answer', () async {
    final (repo, a) = _repo(
      (_) => _json(200, {
        'list_ids': [1, 4],
      }),
    );
    expect(await repo.saveToFavourites(7), {1, 4});
    expect(a.seen.single.method, 'PUT');
    expect(a.seen.single.path, '/lists/default/spots/7');
  });

  test('adds, removes and asks by list and spot', () async {
    final (repo, a) = _repo((_) => _json(200, {'list_ids': <int>[]}));
    await repo.addSpot(3, 7);
    await repo.removeSpot(3, 7);
    await repo.membership(7);
    expect(a.seen.map((o) => '${o.method} ${o.path}'), [
      'PUT /lists/3/spots/7',
      'DELETE /lists/3/spots/7',
      'GET /spots/7/lists',
    ]);
  });

  test('pages through spots with the cursor', () async {
    final (repo, a) = _repo(
      (_) => _json(200, {
        'items': [
          {'id': 5, 'title': 'T', 'lat': 1, 'lon': 2},
        ],
        'next_cursor': 'abc',
      }),
    );
    final page = await repo.spots(3);
    expect(page.items.single.id, 5);
    expect(page.nextCursor, 'abc');
    await repo.spots(3, cursor: 'abc');
    expect(a.seen.last.path, '/lists/3/spots');
    expect(a.seen.last.queryParameters['cursor'], 'abc');
  });

  test('creates, renames and deletes', () async {
    final (repo, a) = _repo(
      (o) => o.method == 'DELETE'
          ? ResponseBody.fromString('', 204)
          : _json(200, {'id': 3, 'name': 'New'}),
    );
    expect((await repo.create('New')).id, 3);
    await repo.rename(3, 'Newer');
    await repo.deleteList(3);
    expect(a.seen.map((o) => '${o.method} ${o.path}'), [
      'POST /lists',
      'PATCH /lists/3',
      'DELETE /lists/3',
    ]);
    expect(a.seen[1].data, {'name': 'Newer'});
  });

  test('a taken name surfaces as its API code', () async {
    final (repo, _) = _repo(
      (_) => _json(409, {
        'error': {'code': 'name_taken', 'message': 'x'},
      }),
    );
    await expectLater(
      repo.create('Dup'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'name_taken')),
    );
  });
}
