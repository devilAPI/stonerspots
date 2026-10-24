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

  @override
  SpotsState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SpotsState();
  }

  /// Location if granted, else the DACH region centre.
  Future<MapView> resolveInitialView() async {
    final pos = await ref.read(locationServiceProvider).currentPosition();
    return pos == null
        ? const MapView(kRegionCentre, kRegionZoom)
        : MapView(pos, kUserZoom, located: true);
  }

  /// Called on every camera move; fetches after the debounce delay.
  void onCameraMoved(LatLngBounds bounds) {
    _bounds = bounds;
    _timer?.cancel();
    _timer = Timer(ref.read(mapDebounceProvider), _fetch);
  }

  void setCategory(String? category) {
    state = category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category);
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
    state = state.copyWith(loading: true, error: false);
    try {
      final spots = await ref
          .read(mapSpotsRepositoryProvider)
          .inBounds(bounds, category: state.category);
      if (id != _seq) return; // a newer request superseded this one
      state = state.copyWith(spots: spots, loading: false);
    } catch (_) {
      if (id != _seq) return;
      state = state.copyWith(loading: false, error: true);
    }
  }
}

final spotsControllerProvider = NotifierProvider<SpotsController, SpotsState>(
  SpotsController.new,
);
