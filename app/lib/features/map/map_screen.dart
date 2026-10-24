import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import 'map_tiles.dart';
import 'spot_cluster_layer.dart';
import 'spot_marker.dart';
import 'spot_preview_sheet.dart';
import 'spots_controller.dart';

const _categories = [
  'bench',
  'river',
  'lake',
  'viewpoint',
  'forest',
  'park',
  'other',
];

String _categoryLabel(AppLocalizations l, String? c) => switch (c) {
  'bench' => l.categoryBench,
  'river' => l.categoryRiver,
  'lake' => l.categoryLake,
  'viewpoint' => l.categoryViewpoint,
  'forest' => l.categoryForest,
  'park' => l.categoryPark,
  'other' => l.categoryOther,
  _ => l.categoryAll,
};

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  bool _deniedShown = false;

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
    if (!view.located && !_deniedShown) {
      _deniedShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).locationDenied)),
      );
    }
    _notifyBounds();
  }

  void _notifyBounds() {
    ref
        .read(spotsControllerProvider.notifier)
        .onCameraMoved(_mapController.camera.visibleBounds);
  }

  void _showPreview(Spot spot) {
    showModalBottomSheet<void>(
      context: context,
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
              buildTileLayer(context),
              SpotClusterLayer(markers: _markers),
              buildMapAttribution(context),
            ],
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in <String?>[null, ..._categories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_categoryLabel(l10n, c)),
                        selected: state.category == c,
                        onSelected: (_) => ref
                            .read(spotsControllerProvider.notifier)
                            .setCategory(c),
                      ),
                    ),
                ],
              ),
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
              child: Material(
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  title: Text(l10n.errorGeneric),
                  trailing: TextButton(
                    onPressed: ref.read(spotsControllerProvider.notifier).retry,
                    child: Text(l10n.retry),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
