import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'spot_marker.dart';
import 'spot_preview_sheet.dart';
import 'spots_controller.dart';

const String kTileUrl = String.fromEnvironment('TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');

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

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final view =
        await ref.read(spotsControllerProvider.notifier).resolveInitialView();
    if (!mounted) return;
    _mapController.move(view.centre, view.zoom);
    if (!view.located && !_deniedShown) {
      _deniedShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).locationDenied)));
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
    final top = state.spots.take(kTopSpots).map((s) => s.id).toSet();
    final markers = [
      for (final s in state.spots)
        buildSpotMarker(s,
            large: top.contains(s.id), onTap: () => _showPreview(s)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.mapTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/spot/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.addSpot),
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: kRegionCentre,
            initialZoom: kRegionZoom,
            onMapReady: _notifyBounds,
            onPositionChanged: (camera, hasGesture) => ref
                .read(spotsControllerProvider.notifier)
                .onCameraMoved(camera.visibleBounds),
          ),
          children: [
            TileLayer(
              urlTemplate: kTileUrl,
              userAgentPackageName: 'de.stonerspots.app',
            ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 60,
                size: const Size(40, 40),
                markers: markers,
                builder: (context, markers) => Container(
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: kAccent, shape: BoxShape.circle),
                  child: Text('${markers.length}',
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
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
              child: LinearProgressIndicator(minHeight: 2)),
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
      ]),
    );
  }
}
