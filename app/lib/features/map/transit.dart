import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;
import '../../l10n/app_localizations.dart';

/// Stops are loaded and shown from this zoom on; further out there would be
/// thousands of them.
const kTransitMinZoom = 13.0;

/// Bus stops are dense; they only show this close.
const kBusMinZoom = 15.0;

/// The backend's cache grid and largest box per request (degrees).
const _cellDeg = 0.05;
const _maxSpan = 0.5;

enum TransitKind { train, subway, tram, bus, ferry }

class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    required this.kind,
    required this.point,
  });

  final String id;
  final String name;
  final TransitKind kind;
  final LatLng point;

  /// Null for a kind this app version does not know.
  static TransitStop? fromJson(Map<String, dynamic> j) {
    final kind = TransitKind.values.asNameMap()[j['kind']];
    if (kind == null) return null;
    return TransitStop(
      id: j['id'] as String,
      name: (j['name'] ?? '') as String,
      kind: kind,
      point: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
    );
  }
}

abstract class TransitRepository {
  Future<List<TransitStop>> stops(LatLngBounds area);
}

class ApiTransitRepository implements TransitRepository {
  ApiTransitRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<TransitStop>> stops(LatLngBounds b) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/transit/stops',
      query: {'bbox': '${b.west},${b.south},${b.east},${b.north}'},
      // the first load of an area waits for OpenStreetMap's public Overpass
      // API, which can take most of a minute
      receiveTimeout: const Duration(seconds: 120),
    );
    return [
      for (final e in (json['stops'] ?? const []) as List)
        ?TransitStop.fromJson(e as Map<String, dynamic>),
    ];
  }
}

final transitRepositoryProvider = Provider<TransitRepository>(
  (ref) => ApiTransitRepository(ref.watch(apiClientProvider)),
);

final transitDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 600),
);

/// Wait before loading again after a failure (busy or slow upstream).
final transitRetryProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 20),
);

class TransitState {
  const TransitState({this.enabled = true, this.stops = const []});
  final bool enabled;
  final List<TransitStop> stops;
}

/// Loads the stops around the viewport. The area is snapped to the
/// backend's cache grid and padded, so small pans need no request; a failed
/// load is retried after [transitRetryProvider] or on the next move.
class TransitController extends Notifier<TransitState> {
  Timer? _timer;
  int _seq = 0;
  LatLngBounds? _view;
  double _zoom = 0;
  LatLngBounds? _loaded;

  @override
  TransitState build() {
    ref.onDispose(() => _timer?.cancel());
    return const TransitState();
  }

  void setEnabled(bool enabled) {
    state = TransitState(enabled: enabled, stops: state.stops);
    if (enabled) _schedule();
  }

  void onCameraMoved(LatLngBounds view, double zoom) {
    _view = view;
    _zoom = zoom;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final view = _view;
    if (!state.enabled || view == null || _zoom < kTransitMinZoom) return;
    if (_loaded?.containsBounds(view) ?? false) return;
    _timer = Timer(ref.read(transitDebounceProvider), _fetch);
  }

  Future<void> _fetch() async {
    final view = _view;
    if (view == null) return;
    final area = gridArea(view);
    final id = ++_seq;
    try {
      final stops = await ref.read(transitRepositoryProvider).stops(area);
      if (id != _seq) return;
      _loaded = area;
      state = TransitState(enabled: state.enabled, stops: stops);
    } catch (_) {
      // The map works without stops; try again a bit later.
      if (id == _seq && state.enabled) {
        _timer?.cancel();
        _timer = Timer(ref.read(transitRetryProvider), _fetch);
      }
    }
  }

  /// The viewport padded by a quarter on each side, snapped outwards to the
  /// backend's cache cells, and at most [_maxSpan] per side around the
  /// centre.
  @visibleForTesting
  static LatLngBounds gridArea(LatLngBounds v) {
    double half(double span) => math.min(span * 0.75, _maxSpan) / 2;
    final cLat = (v.north + v.south) / 2, cLon = (v.east + v.west) / 2;
    final hLat = half(v.north - v.south), hLon = half(v.east - v.west);
    double down(double x) => (x / _cellDeg).floorToDouble() * _cellDeg;
    double up(double x) => (x / _cellDeg).ceilToDouble() * _cellDeg;
    var s = down(cLat - hLat), n = up(cLat + hLat);
    var w = down(cLon - hLon), e = up(cLon + hLon);
    // snapping out may cross the limit by a cell; trim it back on the far side
    if (n - s > _maxSpan + 1e-9) n = s + _maxSpan;
    if (e - w > _maxSpan + 1e-9) e = w + _maxSpan;
    // a hair inside the cell edges, so no neighbouring cell is asked for
    const eps = 1e-6;
    return LatLngBounds(LatLng(s + eps, w + eps), LatLng(n - eps, e - eps));
  }
}

final transitControllerProvider =
    NotifierProvider<TransitController, TransitState>(TransitController.new);

const _colors = {
  TransitKind.train: Color(0xFFEF6C00),
  TransitKind.subway: Color(0xFF1E88E5),
  TransitKind.tram: Color(0xFFE53935),
  TransitKind.bus: Color(0xFF8E24AA),
  TransitKind.ferry: Color(0xFF00ACC1),
};

const _icons = {
  TransitKind.train: Icons.train,
  TransitKind.subway: Icons.subway,
  TransitKind.tram: Icons.tram,
  TransitKind.bus: Icons.directions_bus,
  TransitKind.ferry: Icons.directions_boat,
};

String transitKindLabel(AppLocalizations l, TransitKind k) => switch (k) {
  TransitKind.train => l.transitTrain,
  TransitKind.subway => l.transitSubway,
  TransitKind.tram => l.transitTram,
  TransitKind.bus => l.transitBus,
  TransitKind.ferry => l.transitFerry,
};

/// Small stop icons under the spot markers; tap one for its name. Reads the
/// camera, so bus stops appear and disappear with the zoom.
class TransitStopsLayer extends ConsumerWidget {
  const TransitStopsLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(transitControllerProvider);
    final zoom = MapCamera.of(context).zoom;
    if (!state.enabled || zoom < kTransitMinZoom) return const SizedBox();
    final l10n = AppLocalizations.of(context);
    return MarkerLayer(
      markers: [
        for (final s in state.stops)
          if (s.kind != TransitKind.bus || zoom >= kBusMinZoom)
            Marker(
              key: ValueKey('transit-${s.id}'),
              point: s.point,
              width: 22,
              height: 22,
              child: Tooltip(
                message: s.name.isEmpty
                    ? transitKindLabel(l10n, s.kind)
                    : '${transitKindLabel(l10n, s.kind)} · ${s.name}',
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  decoration: BoxDecoration(
                    color: _colors[s.kind],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(_icons[s.kind], size: 13, color: Colors.white),
                ),
              ),
            ),
      ],
    );
  }
}
