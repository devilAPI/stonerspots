import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/api_client.dart';
import '../../l10n/app_localizations.dart';
import '../map/buildings/map_tilt.dart';
import 'germany.dart';
import 'zone_consent.dart';
import 'zone_geo.dart';
import 'zone_models.dart';
import 'zone_tiles.dart';
import 'zone_time.dart';
import 'zones_repository.dart';

/// Zones show from this zoom on (street level). The server refuses boxes
/// much bigger than a screen at this zoom.
const double kZoneMinZoom = 15;

/// At most this many tiles are loaded for one view (a 4K window at zoom 15
/// needs about 40).
const int _maxViewTiles = 48;

/// Tiles kept drawn-ready; older ones are rebuilt from the tile cache.
const int _maxGraphics = 96;

/// Paths are kept in pixels at this zoom, relative to the tile's corner:
/// small numbers, so the 32-bit floats of a [Path] stay exact to well
/// under a pixel at any zoom.
const double _refZoom = 17;

const _crs = Epsg3857();

/// Translucent colours of the layer; overlapping zones do not get darker
/// (each colour is drawn opaque into one layer that is then faded).
const Color kZoneRed = Color(0xFFE53935);
const Color kZoneYellow = Color(0xFFFDD835);
const Color kZoneGreen = Color(0xFF43A047);
const int _zoneAlpha = 0x50;

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

/// The clock for the pedestrian-zone hours; tests replace it.
final zoneClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// One part of a tile's drawing: areas to fill and lines to stroke with
/// round ends and joins, which together are the geometry grown by the
/// stroke's half width.
class _Bucket {
  final fill = Path();
  final stroke = Path();
  bool hasFill = false;
  bool hasStroke = false;
  double strokeWidth = 0;
}

/// The zones of one tile, turned into paths once when the tile arrives, so
/// a frame only transforms and fills them.
class ZoneTileGraphics {
  ZoneTileGraphics._(this.tile, this.zones, this.origin, this._originPx);

  factory ZoneTileGraphics.build(ZoneTileId tile, List<Zone> zones) {
    final origin = LatLng(tile.north, tile.west);
    final g = ZoneTileGraphics._(
      tile,
      zones,
      origin,
      _crs.latLngToOffset(origin, _refZoom),
    );
    final midLat = (tile.south + tile.north) / 2;
    // metres per pixel at the reference zoom here (Web Mercator)
    final mpp =
        2 *
        math.pi *
        kEarthRadius *
        math.cos(midLat * math.pi / 180) /
        _crs.scale(_refZoom);
    for (final z in zones) {
      final b = z.isPedestrian
          ? g.pedestrian
          : z.kind == ZoneKind.explicit
          ? g.explicit
          : g.facility;
      final r = z.radius / mpp;
      b.strokeWidth = 2 * r;
      for (final part in z.parts) {
        final pts = [for (final p in part) g._local(p)];
        switch (z.shape) {
          case ZoneShape.point:
            if (r > 0) {
              b.fill.addOval(Rect.fromCircle(center: pts.first, radius: r));
              b.hasFill = true;
            }
          case ZoneShape.polygon:
            b.fill.addPolygon(pts, true);
            b.hasFill = true;
            if (r > 0) {
              b.stroke.addPolygon(pts, true);
              b.hasStroke = true;
            }
          case ZoneShape.line:
            b.stroke.addPolygon(pts, false);
            b.hasStroke = true;
        }
      }
    }
    return g;
  }

  final ZoneTileId tile;
  final List<Zone> zones;

  /// North-west corner of the tile.
  final LatLng origin;
  final Offset _originPx;

  final facility = _Bucket();
  final explicit = _Bucket();
  final pedestrian = _Bucket();

  Offset _local(LatLng p) => _crs.latLngToOffset(p, _refZoom) - _originPx;
}

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
  final _failed = <ZoneTileId>{};

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
  /// are asked for again after [zoneRetryProvider].
  void _scheduleRetry() {
    _retry ??= Timer(ref.read(zoneRetryProvider), () {
      _retry = null;
      if (_wanted.any(_failed.contains)) _load();
    });
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
              _failed.remove(t);
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
                _failed.add(t);
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
    final busy = _wanted.any(
      (t) => _loading.contains(t) || _waiting.contains(t),
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
      failed: _wanted.any(_failed.contains),
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

/// The zones drawn on the map (a [FlutterMap] child, above the base map).
/// Shows only while the zone feature is on, the disclaimer read and the
/// map zoomed in to street level.
class ZoneLayer extends ConsumerWidget {
  const ZoneLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(zonesActiveProvider)) return const SizedBox.shrink();
    final camera = MapCamera.of(context);
    if (camera.zoom < kZoneMinZoom) return const SizedBox.shrink();
    ref.read(zoneLayerControllerProvider.notifier).onCamera(camera);
    final s = ref.watch(zoneLayerControllerProvider);
    if (s.tiles.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: MobileLayerTransformer(
        child: CustomPaint(
          key: const Key('zoneLayer'),
          size: camera.size,
          isComplex: true,
          painter: ZonePainter(
            camera: camera,
            tiles: s.tiles.values.toList(growable: false),
            banNow: s.banNow,
          ),
        ),
      ),
    );
  }
}

class ZonePainter extends CustomPainter {
  ZonePainter({
    required this.camera,
    required this.tiles,
    required this.banNow,
  });

  final MapCamera camera;
  final List<ZoneTileGraphics> tiles;
  final bool banNow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.pow(2, camera.zoom - _refZoom).toDouble();
    final view = Offset.zero & size;
    final visible = [
      for (final t in tiles)
        if (_onScreen(t, scale, view)) t,
    ];
    if (visible.isEmpty) return;
    void group(Color color, List<_Bucket> Function(ZoneTileGraphics) of) {
      if (!visible.any((t) => of(t).any((b) => b.hasFill || b.hasStroke))) {
        return;
      }
      canvas.saveLayer(view, Paint()..color = color.withAlpha(_zoneAlpha));
      final fill = Paint()..color = color;
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (final t in visible) {
        canvas.save();
        canvas.translate(
          camera.getOffsetFromOrigin(t.origin).dx,
          camera.getOffsetFromOrigin(t.origin).dy,
        );
        canvas.scale(scale);
        for (final b in of(t)) {
          if (b.hasFill) canvas.drawPath(b.fill, fill);
          if (b.hasStroke) {
            canvas.drawPath(b.stroke, stroke..strokeWidth = b.strokeWidth);
          }
        }
        canvas.restore();
      }
      canvas.restore();
    }

    group(kZoneRed, (t) => [t.facility, t.explicit]);
    group(banNow ? kZoneYellow : kZoneGreen, (t) => [t.pedestrian]);
  }

  /// The tile plus the 100 m around it overlaps the screen.
  bool _onScreen(ZoneTileGraphics t, double scale, Rect view) {
    final nw = camera.getOffsetFromOrigin(t.origin);
    final se = camera.getOffsetFromOrigin(LatLng(t.tile.south, t.tile.east));
    final margin = t.facility.strokeWidth * scale; // >= 100 m in pixels
    return Rect.fromPoints(nw, se).inflate(margin + 2).overlaps(view);
  }

  @override
  bool shouldRepaint(ZonePainter old) =>
      old.camera != camera ||
      old.banNow != banNow ||
      !identical(old.tiles, tiles) && !_sameList(old.tiles, tiles);

  static bool _sameList(List<ZoneTileGraphics> a, List<ZoneTileGraphics> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}

/// Hint, attribution and the first-use disclaimer on top of the map (a
/// [FlutterMap] child after the layers).
class ZoneOverlay extends ConsumerStatefulWidget {
  const ZoneOverlay({super.key, this.top = 72});

  /// Distance of the hint below the top inset (under the filter bar).
  final double top;

  @override
  ConsumerState<ZoneOverlay> createState() => _ZoneOverlayState();
}

class _ZoneOverlayState extends ConsumerState<ZoneOverlay> {
  bool _asked = false;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // also while the layer is off: the button to turn it on hides abroad
    final tilt = MapTiltScope.of(context);
    ref.read(zonesAbroadProvider.notifier).onCamera(camera, tilt);
    if (!ref.watch(zonesEnabledProvider)) return const SizedBox.shrink();
    // no part of Germany on the screen: no zones, no hints (the buttons
    // hide too, see zonesAbroadProvider)
    if (outsideGermany(camera, tilt)) return const SizedBox.shrink();
    final zoomedIn = camera.zoom >= kZoneMinZoom;
    final accepted = ref.watch(zonesAcceptedProvider);
    if (!accepted) {
      // first reach of street level with the layer on: the disclaimer first
      if (zoomedIn && !_asked) {
        _asked = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ensureZoneConsent(context, ref);
        });
      }
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final failed =
        zoomedIn &&
        ref.watch(zoneLayerControllerProvider.select((s) => s.failed));
    final loading =
        zoomedIn &&
        ref.watch(zoneLayerControllerProvider.select((s) => s.loading));
    final insets = MediaQuery.paddingOf(context);
    final pill = !zoomedIn
        ? _Pill(key: const Key('zoneZoomHint'), text: l.zonesZoomHint)
        : failed
        ? _Pill(key: const Key('zoneLoadFailed'), text: l.zonesLoadFailed)
        : loading
        ? _Pill(key: const Key('zoneLoading'), text: l.zonesLoading)
        : null;
    return Stack(
      children: [
        if (pill != null)
          Positioned(
            top: insets.top + widget.top,
            left: insets.left + 72,
            right: insets.right + 72,
            child: IgnorePointer(child: Center(child: pill)),
          ),
        if (zoomedIn)
          Positioned(
            bottom: insets.bottom + 4,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Text(
                  l.zonesAttribution,
                  key: const Key('zoneAttribution'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xB3000000),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}

/// Map control: switches the zone layer; the first time on, the
/// disclaimer comes first.
class ZoneToggleButton extends ConsumerWidget {
  const ZoneToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(zonesAbroadProvider)) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final on = ref.watch(zonesEnabledProvider);
    return IconButton(
      key: const Key('mapZones'),
      tooltip: on ? l.zonesHide : l.zonesShow,
      isSelected: on,
      onPressed: () {
        final enabled = ref.read(zonesEnabledProvider.notifier);
        if (on) {
          enabled.set(false);
          return;
        }
        enabled.set(true);
        ensureZoneConsent(context, ref);
      },
      // the same outline either way; on, it turns red on a red tint
      style: on
          ? IconButton.styleFrom(
              foregroundColor: kZoneRed,
              backgroundColor: kZoneRed.withValues(alpha: 0.16),
            )
          : null,
      icon: const Icon(Icons.do_not_disturb_on_outlined),
    );
  }
}

/// Map control next to [ZoneToggleButton]: the disclaimer again.
class ZoneInfoButton extends ConsumerWidget {
  const ZoneInfoButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(zonesEnabledProvider) || ref.watch(zonesAbroadProvider)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      key: const Key('mapZonesInfo'),
      tooltip: AppLocalizations.of(context).zonesInfo,
      onPressed: () => showZoneDisclaimer(context),
      icon: const Icon(Icons.info_outline),
    );
  }
}

/// A tap on the map: tells what zone is there, if any.
void showZonesAt(BuildContext context, WidgetRef ref, LatLng p, double zoom) {
  if (zoom < kZoneMinZoom || !ref.read(zonesActiveProvider)) return;
  final hits = ref.read(zoneLayerControllerProvider.notifier).hitsAt(p);
  if (hits.isEmpty) return;
  final l = AppLocalizations.of(context);
  final banNow = ref.read(zoneLayerControllerProvider).banNow;
  String line(ZoneHit h) {
    final title = zoneTitle(l, h.zone);
    return switch (h.zone.kind) {
      ZoneKind.pedestrian =>
        banNow
            ? l.zoneTapPedestrianNow(title)
            : l.zoneTapPedestrianLater(title),
      ZoneKind.explicit => l.zoneTapExplicit(title),
      _ => l.zoneTapRadius(title),
    };
  }

  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      key: const Key('zoneTapInfo'),
      content: Text(hits.take(3).map(line).join('\n')),
      action: SnackBarAction(
        label: l.zonesInfo,
        onPressed: () => showZoneDisclaimer(context),
      ),
    ),
  );
}
