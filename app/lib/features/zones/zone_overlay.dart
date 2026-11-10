import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../l10n/app_localizations.dart';
import '../map/buildings/map_tilt.dart';
import 'zone_consent.dart';
import 'zone_geo.dart';
import 'zone_models.dart';
import 'zone_layer_controller.dart';
import 'zone_paint.dart';

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
  if (hits.isEmpty) {
    // a tap where there is no zone puts the last zone notice away
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    return;
  }
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
      // with an action Flutter would keep it until dismissed
      persist: false,
      duration: const Duration(seconds: 6),
      showCloseIcon: true,
      action: SnackBarAction(
        label: l.zonesInfo,
        onPressed: () => showZoneDisclaimer(context),
      ),
    ),
  );
}
