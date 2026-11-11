import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/zones/zone_models.dart';
import 'package:app/features/zones/zone_status.dart';
import 'package:app/features/zones/zone_tiles.dart';
import 'package:app/features/zones/zones_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'zone_fixtures.dart';

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

void main() {
  test('asks GET /zones for exactly one tile and parses the answer', () async {
    final a = _Adapter(
      (o) => _json(200, {
        'zones': [
          {
            'id': 'way/2',
            'kind': 'playground',
            'name': 'Spielplatz Musterweg',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [48.125, 11.565],
                  [48.125, 11.566],
                  [48.126, 11.566],
                  [48.125, 11.565],
                ],
              ],
            },
          },
        ],
        'attribution': '© OpenStreetMap contributors (ODbL)',
        'stale': false,
      }),
    );
    final repo = ApiZonesRepository(
      ApiClient(
        tokenStore: TokenStore.memory(),
        baseUrl: 'http://x/api/v1',
        adapter: a,
      ),
    );
    final d = await repo.fetchTile(const ZoneTileId(2406, 578));
    expect(a.seen.single.path, '/zones');
    expect(a.seen.single.queryParameters, {
      'south': '48.120000',
      'west': '11.560000',
      'north': '48.140000',
      'east': '11.580000',
    });
    expect(d.zones.single.kind, ZoneKind.playground);
    expect(d.stale, isFalse);
  });

  test('zones_pending is retried until the tile is there', () async {
    var calls = 0;
    final adapter = _Adapter((o) {
      calls++;
      return calls < 3
          ? _json(503, {
              'error': {'code': 'zones_pending', 'message': 'later'},
            })
          : _json(200, {'zones': [], 'attribution': 'OSM', 'stale': false});
    });
    final repo = ApiZonesRepository(
      ApiClient(
        tokenStore: TokenStore.memory(),
        baseUrl: 'http://x/api/v1',
        adapter: adapter,
      ),
      pendingWait: Duration.zero,
    );
    final data = await repo.fetchTile(const ZoneTileId(1, 1));
    expect(data.zones, isEmpty);
    expect(calls, 3);
  });

  test('zones_pending gives up after its retries', () async {
    var calls = 0;
    final repo = ApiZonesRepository(
      ApiClient(
        tokenStore: TokenStore.memory(),
        baseUrl: 'http://x/api/v1',
        adapter: _Adapter((o) {
          calls++;
          return _json(503, {
            'error': {'code': 'zones_pending', 'message': 'later'},
          });
        }),
      ),
      pendingRetries: 2,
      pendingWait: Duration.zero,
    );
    await expectLater(
      repo.fetchTile(const ZoneTileId(1, 1)),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'zones_pending'),
      ),
    );
    expect(calls, 3);
  });

  test('errors come through as ApiException', () async {
    final repo = ApiZonesRepository(
      ApiClient(
        tokenStore: TokenStore.memory(),
        baseUrl: 'http://x/api/v1',
        adapter: _Adapter(
          (o) => _json(503, {
            'error': {'code': 'zones_unavailable', 'message': 'later'},
          }),
        ),
      ),
    );
    await expectLater(
      repo.fetchTile(const ZoneTileId(1, 1)),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'zones_unavailable'),
      ),
    );
  });

  group('tile cache', () {
    test('one request per tile, also when asked twice at once', () async {
      final gate = Completer<void>();
      final repo = _SlowRepo(gate.future);
      final cache = ZoneTileCache(repo);
      const t = ZoneTileId(2406, 578);
      final a = cache.tile(t), b = cache.tile(t);
      gate.complete();
      await Future.wait([a, b]);
      await cache.tile(t);
      expect(repo.asked, [t]);
      expect(cache.peek(t), isNotNull);
    });

    test('failures are not cached; an older copy is used instead', () async {
      final repo = FakeZonesRepository()..fail = true;
      final cache = ZoneTileCache(repo);
      const t = ZoneTileId(1, 1);
      await expectLater(cache.tile(t), throwsException);
      repo.fail = false;
      await cache.tile(t);
      expect(repo.asked, [t, t]);
    });

    test('stale data is asked for again after a while', () async {
      var now = DateTime(2026, 1, 1, 12);
      final repo = FakeZonesRepository()..stale = true;
      final cache = ZoneTileCache(repo, now: () => now);
      const t = ZoneTileId(1, 1);
      expect((await cache.tile(t)).stale, isTrue);
      await cache.tile(t);
      expect(repo.asked, hasLength(1));
      now = now.add(const Duration(minutes: 11));
      repo.fail = true; // the refresh fails: the stale copy stays
      expect((await cache.tile(t)).stale, isTrue);
      expect(repo.asked, hasLength(2));
    });

    test('fresh data is asked for again after an hour', () async {
      var now = DateTime(2026, 1, 1, 12);
      final repo = FakeZonesRepository();
      final cache = ZoneTileCache(repo, now: () => now);
      const t = ZoneTileId(1, 1);
      await cache.tile(t);
      now = now.add(const Duration(minutes: 59));
      await cache.tile(t);
      expect(repo.asked, hasLength(1));
      now = now.add(const Duration(minutes: 2));
      await cache.tile(t);
      expect(repo.asked, hasLength(2));
      now = now.add(const Duration(hours: 2));
      repo.fail = true; // the refresh fails: the older copy stays
      expect(await cache.tile(t), isNotNull);
      expect(repo.asked, hasLength(3));
    });

    test('keeps at most maxTiles, dropping the least recently used', () async {
      final repo = FakeZonesRepository();
      final cache = ZoneTileCache(repo, maxTiles: 2);
      await cache.tile(const ZoneTileId(0, 0));
      await cache.tile(const ZoneTileId(0, 1));
      await cache.tile(const ZoneTileId(0, 0)); // used again
      await cache.tile(const ZoneTileId(0, 2));
      expect(cache.peek(const ZoneTileId(0, 0)), isNotNull);
      expect(cache.peek(const ZoneTileId(0, 1)), isNull);
    });

    test('a spot near a tile edge loads the neighbour too', () async {
      final repo = FakeZonesRepository();
      final cache = ZoneTileCache(repo);
      await checkZones(cache, at(0, 0));
      expect(repo.asked, hasLength(1));
      repo.asked.clear();
      // 30 m below the tile's north edge at 48.14
      await checkZones(cache, at(0, (48.14 - base.latitude) * 111320 - 30));
      expect(repo.asked, [const ZoneTileId(2407, 578)]);
    });

    test('checkZones: unknown when no data comes', () async {
      final cache = ZoneTileCache(FakeZonesRepository()..fail = true);
      expect((await checkZones(cache, base)).verdict, ZoneVerdict.unknown);
    });
  });
}

class _SlowRepo implements ZonesRepository {
  _SlowRepo(this.gate);
  final Future<void> gate;
  final asked = <ZoneTileId>[];

  @override
  Future<ZoneData> fetchTile(ZoneTileId tile) async {
    asked.add(tile);
    await gate;
    return const ZoneData(zones: []);
  }
}
