import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import 'zone_models.dart';
import 'zone_tiles.dart';

/// `GET /zones` for one tile. Throws [ApiException] (`invalid_bbox`,
/// `zones_unavailable`, `zones_disabled`, `rate_limited`, and
/// `zones_pending` once the retries are used up).
abstract class ZonesRepository {
  Future<ZoneData> fetchTile(ZoneTileId tile);
}

class ApiZonesRepository implements ZonesRepository {
  ApiZonesRepository(
    this._api, {
    this.pendingRetries = 12,
    this.pendingWait = const Duration(seconds: 10),
  });

  final ApiClient _api;

  /// How often a `zones_pending` answer (the server is still fetching the
  /// tile from Overpass, which can take minutes) is retried, and how long
  /// to wait between tries.
  final int pendingRetries;
  final Duration pendingWait;

  @override
  Future<ZoneData> fetchTile(ZoneTileId tile) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return ZoneData.fromJson(
          await _api.get<Map<String, dynamic>>('/zones', query: tile.query),
        );
      } on ApiException catch (e) {
        if (e.code != 'zones_pending' || attempt >= pendingRetries) rethrow;
        await Future<void>.delayed(pendingWait);
      }
    }
  }
}

final zonesRepositoryProvider = Provider<ZonesRepository>(
  (ref) => ApiZonesRepository(ref.watch(apiClientProvider)),
);

/// Tiles fetched this session, shared by the map layer, the spot status and
/// the add-spot check. Requests for a tile already on the way wait for that
/// one. Data the server marked stale is asked for again after [staleAfter];
/// failures are not cached.
class ZoneTileCache {
  ZoneTileCache(
    this._repo, {
    this.maxTiles = 200,
    this.staleAfter = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ZonesRepository _repo;
  final int maxTiles;
  final Duration staleAfter;
  final DateTime Function() _now;

  // insertion-ordered: the first entry is the least recently used
  final _tiles = <ZoneTileId, (ZoneData, DateTime)>{};
  final _pending = <ZoneTileId, Future<ZoneData>>{};

  /// The tile if it is loaded (fresh or stale), without fetching.
  ZoneData? peek(ZoneTileId id) => _tiles[id]?.$1;

  /// The tile, from memory or the server.
  Future<ZoneData> tile(ZoneTileId id) {
    final hit = _tiles.remove(id);
    if (hit != null) {
      _tiles[id] = hit; // most recently used
      final (data, at) = hit;
      if (!data.stale || _now().difference(at) < staleAfter) {
        return SynchronousFuture(data);
      }
    }
    return _pending[id] ??= _fetch(id, hit?.$1);
  }

  Future<ZoneData> _fetch(ZoneTileId id, ZoneData? old) async {
    try {
      final data = await _repo.fetchTile(id);
      _tiles.remove(id);
      _tiles[id] = (data, _now());
      while (_tiles.length > maxTiles) {
        _tiles.remove(_tiles.keys.first);
      }
      return data;
    } catch (_) {
      if (old != null) return old;
      rethrow;
    } finally {
      unawaited(_pending.remove(id));
    }
  }

  /// The zones of the tiles around [p] (every place within [metres] is
  /// among them). Throws when a tile cannot be loaded.
  Future<ZoneData> zonesNear(LatLng p, double metres) async {
    final tiles = await Future.wait([
      for (final t in tilesAround(p, metres)) tile(t),
    ]);
    final seen = <String>{};
    return ZoneData(
      zones: [
        for (final t in tiles)
          for (final z in t.zones)
            if (seen.add(z.id)) z,
      ],
      stale: tiles.any((t) => t.stale),
    );
  }
}

final zoneTileCacheProvider = Provider<ZoneTileCache>(
  (ref) => ZoneTileCache(ref.watch(zonesRepositoryProvider)),
);
