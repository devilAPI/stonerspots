import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/glass.dart';
import '../../core/location_service.dart';
import '../../core/models.dart';
import '../../core/responsive.dart';
import '../../core/settings.dart';
import '../../l10n/app_localizations.dart';
import '../users/author_link.dart' show userPath;
import '../zones/zone_layer.dart';
import 'buildings/building_layer.dart';
import 'buildings/map_tilt.dart';
import 'map_gestures.dart';
import 'map_compass.dart';
import 'map_controls_theme.dart';
import 'map_filter_bar.dart';
import 'map_flight.dart';
import 'map_tiles.dart';
import 'spot_cluster_layer.dart';
import 'spot_marker.dart';
import 'spot_preview_sheet.dart';
import 'spot_pull_sheet.dart';
import 'spot_search.dart';
import 'spots_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin {
  final _mapController = MapController();
  late final _flight = MapFlight(_mapController, this);

  /// Keeps the map's state when it moves into the tilt (2D <-> 3D).
  final _mapKey = GlobalKey(debugLabel: 'map');

  /// Animates the tilt (the 3D button, settling after a two-finger tilt).
  static const _tiltDuration = Duration(milliseconds: 350);
  late final _tiltAnimation = AnimationController(
    vsync: this,
    duration: _tiltDuration,
  );
  Animation<double>? _tiltTween;

  /// A two-finger tilt is going on (no pinch zoom or twist meanwhile).
  bool _tiltGesture = false;
  final _searchFocus = FocusNode();
  bool _searchOpen = false;
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

  @override
  void dispose() {
    _tiltAnimation.dispose();
    _flight.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Tilts the map to [target] degrees (0: flat 2D), animated, and
  /// remembers whether the map is left in 3D.
  void _tiltTo(double target) {
    final from = ref.read(mapPitchProvider);
    ref.read(map3dProvider.notifier).set(target > 0);
    if (from == target) return;
    _tiltTween?.removeListener(_applyTilt);
    _tiltTween = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _tiltAnimation, curve: Curves.easeInOut),
    )..addListener(_applyTilt);
    _tiltAnimation
      ..duration = MapSettings.reduceMotionOf(context)
          ? Duration.zero
          : _tiltDuration
      ..forward(from: 0);
  }

  /// Going into 3D closer than [kMap3dMaxZoom]: back out to it.
  void _limitZoomFor3d(double pitch) {
    if (pitch <= 0) return;
    final camera = _mapController.camera;
    if (camera.zoom > kMap3dMaxZoom) {
      _mapController.move(camera.center, kMap3dMaxZoom);
    }
  }

  void _applyTilt() =>
      ref.read(mapPitchProvider.notifier).set(_tiltTween!.value);

  /// After a two-finger tilt: nearly flat settles to 2D, else it stays.
  void _settleTilt() {
    setState(() => _tiltGesture = false);
    final pitch = ref.read(mapPitchProvider);
    _tiltTo(pitch < kExitPitch ? 0 : pitch);
  }

  void _openSearch() {
    if (_searchOpen) {
      _searchFocus.requestFocus();
      return;
    }
    setState(() => _searchOpen = true);
    // autofocus would give way to whatever had focus before
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() => setState(() => _searchOpen = false);

  /// A search result: fly there and show its card as a marker tap would.
  void _pickSearchResult(Spot spot) {
    _closeSearch();
    _userMoved = true;
    final camera = _mapController.camera;
    final zoom = camera.zoom < 15 ? 15.0 : camera.zoom;
    // The card covers the lower part of the map: keep the spot above it.
    final lift = camera.nonRotatedSize.height * 0.2;
    final centre = camera.unprojectAtZoom(
      camera.projectAtZoom(LatLng(spot.lat, spot.lon), zoom) + Offset(0, lift),
      zoom,
    );
    _flight
        .fly(centre, zoom, instant: MapSettings.reduceMotionOf(context))
        .then((_) {
          if (mounted) _notifyBounds();
        });
    _showPreview(spot);
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
    showGlassSheet<void>(
      context: context,
      radius: 32,
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
        onOpenAuthor: (userId) {
          Navigator.of(sheetContext).pop();
          context.push(userPath(userId));
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
    final pitch = ref.watch(mapPitchProvider);
    ref.listen(mapPitchProvider, (before, now) {
      if ((before ?? 0) <= 0 && now > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _limitZoomFor3d(now),
        );
      }
    });
    final map3d = pitch > 0;
    final buildings = map3d && ref.watch(buildings3dProvider);
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
          // above the far edge of the tilted 3D map
          if (map3d) const Positioned.fill(child: _Sky()),
          MapGestures(
            controller: _mapController,
            onTiltStart: () => setState(() => _tiltGesture = true),
            onTiltEnd: _settleTilt,
            child: TiltedMap(
              pitch: pitch,
              child: FlutterMap(
                key: _mapKey,
                mapController: _mapController,
                options: MapOptions(
                  interactionOptions: InteractionOptions(
                    flags: mapInteractionFlags(tilting: _tiltGesture),
                  ),
                  maxZoom: map3d ? kMap3dMaxZoom : kMapMaxZoom,
                  initialCenter: kRegionCentre,
                  initialZoom: kRegionZoom,
                  onMapReady: _notifyBounds,
                  onTap: (_, p) =>
                      showZonesAt(context, ref, p, _mapController.camera.zoom),
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture) {
                      _userMoved = true;
                      _flight.stop();
                    }
                    ref
                        .read(spotsControllerProvider.notifier)
                        .onCameraMoved(camera.visibleBounds);
                  },
                ),
                children: [
                  buildBaseLayer(
                    context,
                    base: _base,
                    transitKey: transitKey,
                    tilted: map3d,
                  ),
                  const ZoneLayer(),
                  if (buildings)
                    BuildingLayer(darkBase: isDarkBaseMap(context, _base)),
                  SpotClusterLayer(markers: _markers),
                  UntiltedMapChild(
                    child: SafeArea(
                      top: false,
                      child: buildBaseAttribution(
                        context,
                        base: _base,
                        transitKey: transitKey,
                        buildings: buildings,
                      ),
                    ),
                  ),
                  const UntiltedMapChild(child: ZoneOverlay()),
                ],
              ),
            ),
          ),
          if (!_searchOpen)
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
                child: MapControlsTheme(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MapSearchButton(onPressed: _openSearch),
                      MapLayerButton(
                        key: const Key('mapLayer'),
                        base: _base,
                        onChanged: (b) => setState(() => _base = b),
                      ),
                      IconButton(
                        key: const Key('map3d'),
                        tooltip: l10n.map3d,
                        isSelected: map3d,
                        onPressed: () => _tiltTo(map3d ? 0 : kMapPitch),
                        icon: const Icon(Icons.view_in_ar_outlined),
                      ),
                      const ZoneToggleButton(),
                      const ZoneInfoButton(),
                      IconButton(
                        key: const Key('mapLocateMe'),
                        tooltip: l10n.mapMyLocation,
                        onPressed: _locating ? null : _locateMe,
                        icon: _locating
                            ? const SizedBox.square(
                                dimension: kMapControlIconSize - 2,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.near_me_outlined),
                      ),
                      MapCompass(controller: _mapController),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // In the stack, not Scaffold.floatingActionButton: that one would
          // ignore the padding and sit behind the glass tab bar.
          Positioned(
            right: insets.right + 16,
            bottom: insets.bottom + 16,
            child: GlassFab(
              key: const Key('addSpot'),
              radius: 24,
              onPressed: () => context.push('/spot/new'),
              icon: Icons.add,
              label: Text(l10n.addSpot),
            ),
          ),
          // over the map controls: the results may reach down past them
          if (_searchOpen)
            Positioned(
              top: insets.top + 8,
              left: insets.left + 12,
              right: insets.right + 12,
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: MapSpotSearch(
                    focusNode: _searchFocus,
                    onPick: _pickSearchResult,
                    onClose: _closeSearch,
                  ),
                ),
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

/// The sky above the far edge of the tilted map.
class _Sky extends StatelessWidget {
  const _Sky();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0E1420), Color(0xFF1C2433)]
              : const [Color(0xFFBFD8EE), Color(0xFFE6F0F8)],
          stops: const [0, 0.25],
        ),
      ),
    );
  }
}
