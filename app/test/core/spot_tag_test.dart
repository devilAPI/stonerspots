import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/feed/feed_repository.dart';
import 'package:app/features/spots/spot_api.dart';
import 'package:app/features/spots/spots_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.body);
  final Object body;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_Adapter a) => ApiClient(
  tokenStore: TokenStore.memory(),
  baseUrl: 'http://x/api/v1',
  adapter: a,
);

const _spotJson = {'id': 5, 'title': 't', 'lat': 1, 'lon': 2};

void main() {
  group('SpotTag', () {
    test('canonical order and wire names', () {
      expect(SpotTag.values.map((t) => t.wire), [
        'roof',
        'seating',
        'view',
        'quiet',
        'shade',
        'water',
        'lit',
      ]);
      expect(SpotTag.fromWire('quiet'), SpotTag.quiet);
      expect(SpotTag.fromWire('nope'), isNull);
      expect(SpotTag.fromWire(null), isNull);
    });

    test('encode sorts canonically and joins with commas', () {
      expect(SpotTag.encode([SpotTag.quiet, SpotTag.roof]), 'roof,quiet');
      expect(SpotTag.sorted({SpotTag.lit, SpotTag.view}), [
        SpotTag.view,
        SpotTag.lit,
      ]);
    });
  });

  group('Spot.fromJson', () {
    test('absent tags -> empty, no author', () {
      final s = Spot.fromJson(_spotJson);
      expect(s.tags, isEmpty);
      expect(s.author, isNull);
    });

    test('unknown tags are ignored, known kept in order', () {
      final s = Spot.fromJson({
        ..._spotJson,
        'tags': ['quiet', 'bogus', 'roof'],
      });
      expect(s.tags, [SpotTag.quiet, SpotTag.roof]);
    });

    test('author', () {
      final s = Spot.fromJson({
        ..._spotJson,
        'author': {'id': 3, 'display_name': 'Ann'},
      });
      expect(s.author?.id, 3);
      expect(s.author?.displayName, 'Ann');
    });

    test('feed items carry the tags of their spot', () {
      final i = FeedItem.fromJson({
        'id': 1,
        'created_at': '2026-10-24T10:00:00Z',
        'author': {'id': 1, 'display_name': 'A'},
        'spot': {
          ..._spotJson,
          'tags': ['water'],
        },
      });
      expect(i.spot.tags, [SpotTag.water]);
    });
  });

  group('wire format', () {
    test('createSpot sends tags only when non-empty', () async {
      final a = _Adapter(_spotJson);
      final api = ApiSpotApi(_client(a));
      await api.createSpot(
        const SpotDraft(
          title: 't',
          description: '',
          category: 'bench',
          lat: 1,
          lon: 2,
        ),
      );
      expect((a.seen.last.data as Map).containsKey('tags'), isFalse);
      await api.createSpot(
        const SpotDraft(
          title: 't',
          description: '',
          category: 'bench',
          lat: 1,
          lon: 2,
          tags: [SpotTag.roof, SpotTag.lit],
        ),
      );
      expect((a.seen.last.data as Map)['tags'], ['roof', 'lit']);
    });

    test('setTags PUTs the tag list and parses the spot', () async {
      final a = _Adapter({
        ..._spotJson,
        'tags': ['view'],
      });
      final s = await ApiSpotApi(_client(a)).setTags(5, [SpotTag.view]);
      expect(a.seen.last.method, 'PUT');
      expect(a.seen.last.path, '/spots/5/tags');
      expect(a.seen.last.data, {
        'tags': ['view'],
      });
      expect(s.tags, [SpotTag.view]);
    });

    test('map query carries category and canonical tags', () async {
      final a = _Adapter(<dynamic>[]);
      final repo = ApiSpotsRepository(_client(a));
      final b = LatLngBounds(const LatLng(1, 2), const LatLng(3, 4));
      await repo.inBounds(
        b,
        category: 'bench',
        tags: const [SpotTag.roof, SpotTag.quiet],
      );
      expect(a.seen.last.queryParameters['tags'], 'roof,quiet');
      expect(a.seen.last.queryParameters['category'], 'bench');
      await repo.inBounds(b);
      expect(a.seen.last.queryParameters.containsKey('tags'), isFalse);
    });

    test('feed query carries tags next to sort and cursor', () async {
      final a = _Adapter({'items': [], 'next_cursor': null});
      final repo = ApiFeedRepository(_client(a));
      await repo.fetch(
        sort: FeedSort.top,
        category: 'lake',
        cursor: 'c',
        tags: const [SpotTag.shade, SpotTag.lit],
      );
      final q = a.seen.last.queryParameters;
      expect(q['tags'], 'shade,lit');
      expect(q['sort'], 'top');
      expect(q['category'], 'lake');
      expect(q['cursor'], 'c');
      await repo.fetch(sort: FeedSort.top);
      expect(a.seen.last.queryParameters.containsKey('tags'), isFalse);
    });
  });

  group('admin', () {
    const base = {
      'id': 1,
      'created_at': '2026-10-24T10:00:00Z',
      'author': {'id': 1, 'display_name': 'A'},
    };

    test('AdminSpot parses tags', () {
      expect(
        AdminSpot.fromJson({
          ...base,
          'tags': ['roof', 'x'],
        }).tags,
        [SpotTag.roof],
      );
      expect(AdminSpot.fromJson(base).tags, isEmpty);
    });

    test('AdminSpotPatch serializes tags only when set', () {
      expect(const AdminSpotPatch(title: 'x').toJson(), {'title': 'x'});
      const p = AdminSpotPatch(tags: [SpotTag.roof, SpotTag.water]);
      expect(p.isEmpty, isFalse);
      expect(p.toJson(), {
        'tags': ['roof', 'water'],
      });
      // clearing all tags is a change too
      expect(const AdminSpotPatch(tags: []).toJson(), {'tags': <String>[]});
    });
  });
}
