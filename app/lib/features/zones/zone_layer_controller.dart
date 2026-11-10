import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/api_client.dart';
import '../map/buildings/map_tilt.dart';
import 'germany.dart';
import 'zone_geo.dart';
import 'zone_tiles.dart';
import 'zone_time.dart';
import 'zones_repository.dart';
import 'zone_paint.dart';

/// Zones show from this zoom on (street level). The server refuses boxes
/// much bigger than a screen at this zoom.
const double kZoneMinZoom = 15;

/// At most this many tiles are loaded for one view (a 4K window at zoom 15
/// needs about 40).
const int _maxViewTiles = 48;

/// Tiles kept drawn-ready; older ones are rebuilt from the tile cache.
const int _maxGraphics = 96;

/// Debounce for loading tiles after the map moved; tests set it to zero.
final zoneDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 350),
);

/// Whether the view shows no part of Germany, at any zoom. The zone
/// buttons hide then (zones exist only in Germany). Fed by [ZoneOverlay],
/// which rebuilds with every camera change.
final zonesAbroadProvider = NotifierProvider<ZonesAbroad, bool>(
  ZonesAbroad.new,
);

class ZonesAbroad extends Notifier<bool> {
  @override
  bool build() => false;

  /// May be called during build: the new value is set right after.
  void onCamera(MapCamera camera, MapTilt? tilt) {
    final abroad = outsideGermany(camera, tilt);
    if (abroad == state) return;
    scheduleMicrotask(() {
      if (ref.mounted) state = abroad;
    });
  }
}

/// Whether the screen shows no part of Germany. Not the camera's
/// visibleBounds: tilted, the map is much larger than the screen, and
/// turned, its box is larger than the map; the screen's own corners are
/// used, through the tilt.
bool outsideGermany(MapCamera camera, MapTilt? tilt) {
  final size = camera.nonRotatedSize;
  final corners =
      tilt?.visibleGround ??
      [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ];
  return !touchesGermanyArea([
    for (final c in corners) camera.screenOffsetToLatLng(c),
  ]);
}

/// How long a tile the server is still fetching from Overpass waits before
/// it is asked for again ("zones_pending": not a failure, just slow).
final zonePendingRetryProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 10),
);

/// A view still loading after this long says so ("Loading zones…"); quicker
/// loads (the server's cache) show nothing.
const Duration kZoneSlowLoad = Duration(milliseconds: 1500);

/// How long a tile that could not be loaded waits before it is asked for
/// again while it is in view (the server itself waits a minute before it
/// asks Overpass for a failed tile again).
final zoneRetryProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 60),
);

/// The first retries of a failed tile come sooner: Overpass is often down
/// only for a moment, and the server tries other Overpass servers.
final zoneQuickRetryProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

/// A tile counts as failed, with the "could not be loaded" note, only after
/// this many failures in a row; before that it is still "loading".
const int kZoneFailuresShown = 3;

/// The clock for the pedestrian-zone hours; tests replace it.
final zoneClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class ZoneLayerState {
  const ZoneLayerState({
    this.tiles = const {},
    this.failed = false,
    this.loading = false,
    this.banNow = false,
  });

  /// Loaded tiles, ready to draw.
  final Map<ZoneTileId, ZoneTileGraphics> tiles;

  /// A tile of the current view could not be loaded.
  final bool failed;

  /// Tiles of the current view have been on their way for a while (the
  /// server is fetching them from Overpass).
  final bool loading;

  /// Pedestrian zones are forbidden right now (7-20 h German time).
  final bool banNow;

  ZoneLayerState copyWith({
    Map<ZoneTileId, ZoneTileGraphics>? tiles,
    bool? failed,
    bool? loading,
    bool? banNow,
  }) => ZoneLayerState(
    tiles: tiles ?? this.tiles,
    failed: failed ?? this.failed,
    loading: loading ?? this.loading,
    banNow: banNow ?? this.banNow,
  );
}

/// Loads the tiles of the map's view (debounced) and keeps them drawn-ready.
class ZoneLayerController extends Notifier<ZoneLayerState> {
  Timer? _debounce;
  Timer? _clock;
  Timer? _retry;
  Timer? _pendingRetry;
  Timer? _slow;

  /// The view has been loading for [kZoneSlowLoad] (set by [_slow]).
  bool _slowLoad = false;
  List<ZoneTileId> _wanted = const [];
  final _graphics = <ZoneTileId, ZoneTileGraphics>{}; // insertion order
  final _loading = <ZoneTileId>{};

  /// Failures in a row of each tile that has not loaded yet.
  final _failures = <ZoneTileId, int>{};
  bool _shownFailed(ZoneTileId t) => (_failures[t] ?? 0) >= kZoneFailuresShown;

  /// Tiles the server is still fetching: asked for again soon, never shown
  /// as failed.
  final _waiting = <ZoneTileId>{};

  @override
  ZoneLayerState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      _clock?.cancel();
      _retry?.cancel();
      _pendingRetry?.cancel();
      _slow?.cancel();
    });
    final now = ref.watch(zoneClockProvider);
    _scheduleClock(now);
    return ZoneLayerState(banNow: pedestrianBanActive(now()));
  }

  void _scheduleClock(DateTime Function() now) {
    _clock?.cancel();
    final wait = nextPedestrianChange(now()).difference(now());
    _clock = Timer(wait + const Duration(seconds: 1), () {
      state = state.copyWith(banNow: pedestrianBanActive(now()));
      _scheduleClock(now);
    });
  }

  /// Called with every camera change while the layer shows. Changes no
  /// state right away, so it may be called during build.
  void onCamera(MapCamera camera) {
    if (camera.zoom < kZoneMinZoom) return;
    final b = camera.visibleBounds;
    // no zones outside Germany: those tiles are never asked for
    var tiles = tilesCovering(
      b.south,
      b.west,
      b.north,
      b.east,
    ).where((t) => touchesGermany(t.south, t.west, t.north, t.east)).toList();
    if (tiles.length > _maxViewTiles) {
      final c = ZoneTileId.at(camera.center.latitude, camera.center.longitude);
      tiles = [...tiles]
        ..sort(
          (a, b) => ((a.y - c.y).abs() + (a.x - c.x).abs()).compareTo(
            (b.y - c.y).abs() + (b.x - c.x).abs(),
          ),
        );
      tiles = tiles.take(_maxViewTiles).toList();
    }
    if (_sameTiles(tiles, _wanted)) return;
    _wanted = tiles;
    _debounce?.cancel();
    final wait = ref.read(zoneDebounceProvider);
    if (wait == Duration.zero) {
      scheduleMicrotask(_load);
    } else {
      _debounce = Timer(wait, _load);
    }
  }

  /// Tiles the server is still fetching are asked for again after
  /// [zonePendingRetryProvider], as long as they are in view.
  void _schedulePendingRetry() {
    _pendingRetry ??= Timer(ref.read(zonePendingRetryProvider), () {
      _pendingRetry = null;
      final again = _waiting.where(_wanted.contains).toList();
      _waiting.clear();
      if (again.isNotEmpty) _load();
    });
  }

  /// Overpass is often only briefly overloaded: failed tiles still in view
  /// are asked for again, soon ([zoneQuickRetryProvider]) until they count
  /// as failed, then every [zoneRetryProvider].
  void _scheduleRetry() {
    final quick = !_wanted.any(_shownFailed);
    _retry ??= Timer(
      ref.read(quick ? zoneQuickRetryProvider : zoneRetryProvider),
      () {
        _retry = null;
        if (_wanted.any(_failures.containsKey)) _load();
      },
    );
  }

  static bool _sameTiles(List<ZoneTileId> a, List<ZoneTileId> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _load() {
    final cache = ref.read(zoneTileCacheProvider);
    for (final t in _wanted) {
      if (_graphics.containsKey(t) || _loading.contains(t)) continue;
      _loading.add(t);
      cache
          .tile(t)
          .then(
            (data) {
              _loading.remove(t);
              _failures.remove(t);
              _waiting.remove(t);
              _graphics[t] = ZoneTileGraphics.build(t, data.zones);
              _publish();
            },
            onError: (Object e) {
              _loading.remove(t);
              if (e is ApiException && e.code == 'zones_pending') {
                // slow, not broken: keep saying "loading" and ask again
                _waiting.add(t);
                _schedulePendingRetry();
              } else {
                _failures[t] = (_failures[t] ?? 0) + 1;
                _scheduleRetry();
              }
              _publish();
            },
          );
    }
    _publish();
  }

  /// Drawn tiles: the wanted ones that are loaded (the rest stay in
  /// [_graphics] for panning back, up to [_maxGraphics]).
  void _publish() {
    while (_graphics.length > _maxGraphics) {
      final old = _graphics.keys.firstWhere(
        (k) => !_wanted.contains(k),
        orElse: () => _graphics.keys.first,
      );
      _graphics.remove(old);
    }
    // a tile that failed, but not often enough to say so, is still coming
    final busy = _wanted.any(
      (t) =>
          _loading.contains(t) ||
          _waiting.contains(t) ||
          (_failures.containsKey(t) && !_shownFailed(t)),
    );
    if (!busy) {
      _slow?.cancel();
      _slow = null;
      _slowLoad = false;
    } else if (_slow == null && !_slowLoad) {
      _slow = Timer(kZoneSlowLoad, () {
        _slow = null;
        _slowLoad = true;
        _publish();
      });
    }
    state = state.copyWith(
      tiles: {for (final t in _wanted) t: ?_graphics[t]},
      failed: _wanted.any(_shownFailed),
      loading: busy && _slowLoad,
    );
  }

  /// The zones at [p] among the loaded tiles, facility zones first.
  List<ZoneHit> hitsAt(LatLng p) {
    final seen = <String>{};
    return zonesAt(p, [
      for (final g in state.tiles.values)
        for (final z in g.zones)
          if (seen.add(z.id)) z,
    ]);
  }
}

final zoneLayerControllerProvider =
    NotifierProvider<ZoneLayerController, ZoneLayerState>(
      ZoneLayerController.new,
    );
