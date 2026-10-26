import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import 'map_filter_bar.dart';
import 'map_tiles.dart';
import 'spot_cluster_layer.dart';
import 'spot_marker.dart';
import 'spot_preview_sheet.dart';
import 'spots_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  bool _deniedShown = false;
  bool _locating = false;
  bool _satellite = false;
  bool _transit = false;

  /// Set once the user drags/zooms; the late location result must then not
  /// yank the camera away from where they are looking.
  bool _userMoved = false;

  // The cluster layer re-clusters whenever the *identity* of the marker list
  // changes, so only rebuild it when the spots themselves change (not when
  // e.g. `loading` toggles).
  List<Spot>? _markerSource;
  List<Marker> _markers = const [];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final view = await ref
        .read(spotsControllerProvider.notifier)
        .resolveInitialView();
    if (!mounted) return;
    if (!_userMoved) _mapController.move(view.centre, view.zoom);
    _notifyBounds();
    final later = view.later;
    if (later != null) {
      // Still waiting for an answer (the browser asks the user): an allow
      // that comes later still brings the map to them.
      _goTo(await later);
    } else if (!view.located) {
      _showDenied();
    }
  }

  /// "My location" button: asks again, e.g. after allowing it in the
  /// browser's site settings.
  Future<void> _locateMe() async {
    setState(() => _locating = true);
    final pos = await ref.read(locationServiceProvider).currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    _goTo(pos, always: true);
  }

  void _goTo(LatLng? pos, {bool always = false}) {
    if (!mounted) return;
    if (pos == null) {
      _showDenied(always: always);
      return;
    }
    _mapController.move(pos, kUserZoom);
    _notifyBounds();
  }

  void _showDenied({bool always = false}) {
    if (_deniedShown && !always) return;
    _deniedShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).locationDenied)),
    );
  }

  void _notifyBounds() {
    ref
        .read(spotsControllerProvider.notifier)
        .onCameraMoved(_mapController.camera.visibleBounds);
  }

  void _showPreview(Spot spot) {
    showModalBottomSheet<void>(
      context: context,
      // full height available (landscape phones are short) but never wider
      // than a comfortable card on big windows
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SpotPreviewSheet(
        spot: spot,
        onOpen: () {
          Navigator.of(sheetContext).pop();
          context.push('/spot/${spot.id}');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(spotsControllerProvider);
    final transitKey = ref.watch(thunderforestKeyProvider);
    if (!identical(_markerSource, state.spots)) {
      _markerSource = state.spots;
      final top = state.spots.take(kTopSpots).map((s) => s.id).toSet();
      _markers = [
        for (final s in state.spots)
          buildSpotMarker(
            s,
            large: top.contains(s.id),
            onTap: () => _showPreview(s),
          ),
      ];
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mapTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/spot/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.addSpot),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              maxZoom: kMapMaxZoom,
              initialCenter: kRegionCentre,
              initialZoom: kRegionZoom,
              onMapReady: _notifyBounds,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) _userMoved = true;
                ref
                    .read(spotsControllerProvider.notifier)
                    .onCameraMoved(camera.visibleBounds);
              },
            ),
            children: [
              buildBaseLayer(
                context,
                satellite: _satellite,
                transit: _transit,
                transitKey: transitKey,
              ),
              SpotClusterLayer(markers: _markers),
              buildBaseAttribution(
                context,
                satellite: _satellite,
                transit: _transit,
              ),
            ],
          ),
          Positioned(top: 8, left: 0, right: 0, child: const MapFilterBar()),
          // below the filter chips
          Positioned(
            top: 64,
            right: 12,
            child: Column(
              spacing: 4,
              children: [
                MapLayerToggle(
                  key: const Key('mapLayer'),
                  satellite: _satellite,
                  onChanged: (v) => setState(() {
                    _satellite = v;
                    if (v) _transit = false;
                  }),
                  streetsLabel: l10n.mapStreets,
                  satelliteLabel: l10n.mapSatellite,
                ),
                if (hasTransitMap(key: transitKey))
                  IconButton.filledTonal(
                    key: const Key('mapTransit'),
                    isSelected: _transit,
                    tooltip: _transit ? l10n.transitHide : l10n.transitShow,
                    onPressed: () => setState(() {
                      _transit = !_transit;
                      if (_transit) _satellite = false;
                    }),
                    icon: const Icon(Icons.directions_transit_outlined),
                    selectedIcon: const Icon(Icons.directions_transit),
                  ),
                IconButton.filledTonal(
                  key: const Key('mapLocateMe'),
                  tooltip: l10n.mapMyLocation,
                  onPressed: _locating ? null : _locateMe,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          if (state.loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (state.error)
            Positioned(
              bottom: 88,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      title: Text(l10n.errorGeneric),
                      trailing: TextButton(
                        onPressed: ref
                            .read(spotsControllerProvider.notifier)
                            .retry,
                        child: Text(l10n.retry),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
