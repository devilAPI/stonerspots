import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../core/glass.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import 'map_filter_bar.dart';
import 'map_tiles.dart';
import 'spot_cluster_layer.dart';
import 'spot_marker.dart';
import 'spot_preview_sheet.dart';
import 'spot_pull_sheet.dart';
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
  MapBase _base = MapBase.streets;

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
    // Narrow windows: the card pulls up into the page. On wider ones the
    // sheet is narrower than the page, so it stays a card with a button.
    if (!context.useNavRail) {
      showSpotPullSheet(context, spot);
      return;
    }
    showLiquidGlassSheet<void>(
      context: context,
      style: glassStyle(radius: 32),
      foregroundColor: kOnGlass,
      padding: EdgeInsets.zero,
      // above the floating tab bar, which lives outside this tab's navigator
      useRootNavigator: true,
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
    // Only the spots: loading/error have their own small widgets, so a fetch
    // does not rebuild the map itself.
    final spots = ref.watch(spotsControllerProvider.select((s) => s.spots));
    final transitKey = ref.watch(thunderforestKeyProvider);
    if (!identical(_markerSource, spots)) {
      _markerSource = spots;
      final top = spots.take(kTopSpots).map((s) => s.id).toSet();
      _markers = [
        for (final s in spots)
          buildSpotMarker(
            s,
            large: top.contains(s.id),
            onTap: () => _showPreview(s),
          ),
      ];
    }

    // The map runs edge to edge, under the status bar and the shell's glass
    // navigation; its padding says what those cover.
    final insets = MediaQuery.paddingOf(context);
    return Scaffold(
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
              buildBaseLayer(context, base: _base, transitKey: transitKey),
              SpotClusterLayer(markers: _markers),
              SafeArea(
                top: false,
                child: buildBaseAttribution(context, base: _base),
              ),
            ],
          ),
          Positioned(
            top: insets.top + 8,
            left: insets.left + 12,
            right: insets.right + 12,
            child: const MapFilterBar(),
          ),
          // below the filter chips
          Positioned(
            top: insets.top + 72,
            right: insets.right + 12,
            child: SizedBox(
              width: 52,
              child: GlassSurface(
                radius: 26,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MapLayerButton(
                      key: const Key('mapLayer'),
                      base: _base,
                      transitKey: transitKey,
                      onChanged: (b) => setState(() => _base = b),
                    ),
                    IconButton(
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
            ),
          ),
          // In the stack, not Scaffold.floatingActionButton: that one would
          // ignore the padding and sit behind the glass tab bar.
          Positioned(
            right: insets.right + 16,
            bottom: insets.bottom + 16,
            child: LiquidGlassFab.extended(
              key: const Key('addSpot'),
              style: glassStyle(radius: 24),
              foregroundColor: kOnGlass,
              onPressed: () => context.push('/spot/new'),
              icon: Icons.add,
              label: Text(l10n.addSpot),
            ),
          ),
          const _LoadingBar(),
          const _ErrorBanner(),
        ],
      ),
    );
  }
}

class _LoadingBar extends ConsumerWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(spotsControllerProvider.select((s) => s.loading))
      ? Positioned(
          top: MediaQuery.paddingOf(context).top,
          left: 0,
          right: 0,
          child: const LinearProgressIndicator(minHeight: 2),
        )
      : const SizedBox.shrink();
}

class _ErrorBanner extends ConsumerWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(spotsControllerProvider.select((s) => s.error))) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Positioned(
      bottom: MediaQuery.paddingOf(context).bottom + 88,
      left: 16,
      right: 16,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Material(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.errorContainer,
            // ListTile would add the shell's navigation padding as well
            child: MediaQuery.removePadding(
              context: context,
              removeLeft: true,
              removeRight: true,
              child: ListTile(
                title: Text(l10n.errorGeneric),
                trailing: TextButton(
                  onPressed: ref.read(spotsControllerProvider.notifier).retry,
                  child: Text(l10n.retry),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
