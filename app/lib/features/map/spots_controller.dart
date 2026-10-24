import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location_service.dart';
import '../../core/models.dart';
import '../spots/spots_repository.dart';

const kRegionCentre = LatLng(49.5, 10.5);
const kRegionZoom = 6.0;
const kUserZoom = 13.0;

/// Number of nicest spots (the API returns best first) drawn larger.
const kTopSpots = 5;

final mapDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 400),
);

/// Upper bound for the first location lookup; a slow or missing location
/// service must not leave the map waiting (or jumping later).
final mapLocationTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 4),
);

class MapView {
  const MapView(this.centre, this.zoom, {this.located = false});
  final LatLng centre;
  final double zoom;
  final bool located;
}

class SpotsState {
  const SpotsState({
    this.spots = const [],
    this.loading = false,
    this.error = false,
    this.category,
  });

  final List<Spot> spots;
  final bool loading;
  final bool error;
  final String? category;

  SpotsState copyWith({
    List<Spot>? spots,
    bool? loading,
    bool? error,
    String? category,
    bool clearCategory = false,
  }) => SpotsState(
    spots: spots ?? this.spots,
    loading: loading ?? this.loading,
    error: error ?? this.error,
    category: clearCategory ? null : (category ?? this.category),
  );
}

class SpotsController extends Notifier<SpotsState> {
  Timer? _timer;
  int _seq = 0;
  LatLngBounds? _bounds;

  // The padded area the current `state.spots` were loaded for. While the
  // viewport stays inside it (and the result was complete) nothing is
  // refetched, so markers do not pop in/out or re-cluster while moving.
  LatLngBounds? _loaded;
  bool _loadedTruncated = false;

  @override
  SpotsState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SpotsState();
  }

  /// Location if granted, else the DACH region centre.
  Future<MapView> resolveInitialView() async {
    final pos = await ref
        .read(locationServiceProvider)
        .currentPosition()
        .timeout(ref.read(mapLocationTimeoutProvider), onTimeout: () => null);
    return pos == null
        ? const MapView(kRegionCentre, kRegionZoom)
        : MapView(pos, kUserZoom, located: true);
  }

  /// Called on every camera move; fetches after the debounce delay.
  void onCameraMoved(LatLngBounds bounds) {
    _bounds = bounds;
    _timer?.cancel();
    if (_coveredByLoaded(bounds)) return;
    _timer = Timer(ref.read(mapDebounceProvider), _fetch);
  }

  void setCategory(String? category) {
    state = category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category);
    _loaded = null;
    _timer?.cancel();
    if (_bounds != null) _fetch();
  }

  void retry() {
    if (_bounds != null) _fetch();
  }

  Future<void> _fetch() async {
    final bounds = _bounds;
    if (bounds == null) return;
    final id = ++_seq;
    final area = _padded(bounds);
    state = state.copyWith(loading: true, error: false);
    try {
      final spots = await ref
          .read(mapSpotsRepositoryProvider)
          .inBounds(area, category: state.category);
      if (id != _seq) return; // a newer request superseded this one
      _loaded = area;
      _loadedTruncated = spots.length >= kMapSpotLimit;
      // Same spots again: keep the very same list so the map does not
      // rebuild and re-cluster its markers for nothing.
      final same = _sameSpots(state.spots, spots);
      state = state.copyWith(spots: same ? state.spots : spots, loading: false);
    } catch (_) {
      if (id != _seq) return;
      state = state.copyWith(loading: false, error: true);
    }
  }

  bool _coveredByLoaded(LatLngBounds view) {
    final loaded = _loaded;
    return loaded != null && !_loadedTruncated && loaded.containsBounds(view);
  }

  /// The viewport grown by half its size on every side, so small pans stay
  /// inside already-loaded data.
  static LatLngBounds _padded(LatLngBounds b) {
    final dLat = (b.north - b.south) * 0.5;
    final dLon = (b.east - b.west) * 0.5;
    return LatLngBounds(
      LatLng(
        (b.south - dLat).clamp(-85.0, 85.0),
        (b.west - dLon).clamp(-180.0, 180.0),
      ),
      LatLng(
        (b.north + dLat).clamp(-85.0, 85.0),
        (b.east + dLon).clamp(-180.0, 180.0),
      ),
    );
  }

  static bool _sameSpots(List<Spot> a, List<Spot> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].likeCount != b[i].likeCount) return false;
    }
    return true;
  }
}

final spotsControllerProvider = NotifierProvider<SpotsController, SpotsState>(
  SpotsController.new,
);
