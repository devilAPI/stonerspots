import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme.dart';

/// Markers closer than this (screen px) are drawn as one number bubble.
const double kClusterRadius = 60;

/// From this zoom on every marker is drawn on its own.
const int kNoClusterZoom = 17;

/// Groups [points] (pixel positions at one zoom level) that lie within
/// [radius] of each other. Greedy in list order, so the first point of a
/// group (the API sends the nicest spots first) is the one it forms around.
/// A grid of [radius]-sized cells keeps the neighbour search linear.
List<List<int>> clusterIndices(List<Offset> points, double radius) {
  final cells = <(int, int), List<int>>{};
  (int, int) cellOf(Offset p) =>
      ((p.dx / radius).floor(), (p.dy / radius).floor());
  for (var i = 0; i < points.length; i++) {
    (cells[cellOf(points[i])] ??= []).add(i);
  }
  final taken = List<bool>.filled(points.length, false);
  final groups = <List<int>>[];
  final r2 = radius * radius;
  for (var i = 0; i < points.length; i++) {
    if (taken[i]) continue;
    taken[i] = true;
    final group = [i];
    final (cx, cy) = cellOf(points[i]);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        for (final j in cells[(cx + dx, cy + dy)] ?? const <int>[]) {
          if (!taken[j] && (points[j] - points[i]).distanceSquared <= r2) {
            taken[j] = true;
            group.add(j);
          }
        }
      }
    }
    groups.add(group);
  }
  return groups;
}

/// Clusters [markers]; tapping a number bubble zooms in so it splits.
///
/// Clusters are worked out once per whole zoom level and kept, so moving the
/// map costs no more than a plain [MarkerLayer] (which also skips everything
/// off screen). A new [markers] list (compared by identity) starts over.
class SpotClusterLayer extends StatefulWidget {
  const SpotClusterLayer({super.key, required this.markers});

  final List<Marker> markers;

  @override
  State<SpotClusterLayer> createState() => _SpotClusterLayerState();
}

class _SpotClusterLayerState extends State<SpotClusterLayer>
    with SingleTickerProviderStateMixin {
  /// Marker positions at zoom 0; at zoom z they are 2^z times as far out.
  List<Offset>? _projected;
  final _byZoom = <int, List<Marker>>{};

  late final _zoomIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  @override
  void didUpdateWidget(SpotClusterLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.markers, widget.markers)) {
      _projected = null;
      _byZoom.clear();
    }
  }

  @override
  void dispose() {
    _zoomIn.dispose();
    super.dispose();
  }

  List<Marker> _atZoom(MapCamera camera, int zoom) {
    final projected = _projected ??= [
      for (final m in widget.markers) camera.projectAtZoom(m.point, 0),
    ];
    final scale = (1 << zoom).toDouble();
    final groups = clusterIndices([
      for (final p in projected) p * scale,
    ], kClusterRadius);
    return [
      for (final g in groups)
        if (g.length == 1)
          widget.markers[g.single]
        else
          _clusterMarker(zoom, [for (final i in g) widget.markers[i]]),
    ];
  }

  Marker _clusterMarker(int zoom, List<Marker> members) {
    final points = [for (final m in members) m.point];
    final lat = points.fold(0.0, (s, p) => s + p.latitude) / points.length;
    final lon = points.fold(0.0, (s, p) => s + p.longitude) / points.length;
    return Marker(
      key: ValueKey(
        'cluster-$zoom-${members.first.key ?? members.first.point}',
      ),
      point: LatLng(lat, lon),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () => _zoomTo(points),
        child: _Bubble(count: members.length),
      ),
    );
  }

  /// Animates the camera onto [points], at least one zoom level closer so
  /// the cluster splits.
  void _zoomTo(List<LatLng> points) {
    final controller = MapController.of(context);
    final from = MapCamera.of(context);
    final fitted = CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.all(48),
      maxZoom: kNoClusterZoom.toDouble(),
    ).fit(from);
    final toZoom = fitted.zoom < from.zoom.floor() + 1
        ? from.zoom.floor() + 1.0
        : fitted.zoom;
    final zoom = Tween(begin: from.zoom, end: toZoom);
    final lat = Tween(begin: from.center.latitude, end: fitted.center.latitude);
    final lon = Tween(
      begin: from.center.longitude,
      end: fitted.center.longitude,
    );
    final curve = CurvedAnimation(parent: _zoomIn, curve: Curves.easeInOut);
    void step() => controller.move(
      LatLng(lat.evaluate(curve), lon.evaluate(curve)),
      zoom.evaluate(curve),
    );
    _zoomIn
      ..stop()
      ..reset();
    _zoomIn.addListener(step);
    _zoomIn.forward().whenCompleteOrCancel(() => _zoomIn.removeListener(step));
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final zoom = camera.zoom.floor();
    final markers = zoom >= kNoClusterZoom
        ? widget.markers
        : _byZoom[zoom] ??= _atZoom(camera, zoom);
    return MarkerLayer(markers: markers);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
    child: Center(
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );
}
