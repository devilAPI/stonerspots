import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/models.dart';
import '../reviews/rating_widgets.dart';

const _distance = Distance(calculator: Haversine());

/// Closer than this to the previous position counts as not having moved.
const kSamePlaceMeters = 100.0;

/// How many tags the widget lists.
const kWidgetTags = 3;

/// [spot] and how far it is from a position.
typedef SpotDistance = ({Spot spot, double meters});

/// The spot of [spots] closest to [position], null when there are none.
SpotDistance? nearestSpot(LatLng position, Iterable<Spot> spots) {
  SpotDistance? best;
  for (final spot in spots) {
    final meters = _distance(position, LatLng(spot.lat, spot.lon));
    if (best == null || meters < best.meters) {
      best = (spot: spot, meters: meters);
    }
  }
  return best;
}

/// `850 m`, `1,2 km` (`1.2 km` in English), `23 km`. Metres are rounded to
/// tens: the position behind them may be days old.
String formatDistance(double meters, String languageCode) {
  if (meters < 995) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  if (km >= 9.95) return '${km.round()} km';
  final text = km.toStringAsFixed(1);
  return '${languageCode == 'en' ? text : text.replaceAll('.', ',')} km';
}

/// What the "nearest spot" widget shows. The JSON goes to the Android side
/// as is; it holds no coordinates, only the id and texts ready to display.
sealed class NearestSpotPayload {
  const NearestSpotPayload();

  Map<String, Object> toJson();

  String encode() => jsonEncode(toJson());
}

/// The app has no position to measure from.
class NoLocationPayload extends NearestSpotPayload {
  const NoLocationPayload();

  @override
  Map<String, Object> toJson() => const {'state': 'no_location'};
}

/// The map around the user has no spots.
class NoSpotsPayload extends NearestSpotPayload {
  const NoSpotsPayload();

  @override
  Map<String, Object> toJson() => const {'state': 'no_spots'};
}

class SpotPayload extends NearestSpotPayload {
  SpotPayload(SpotDistance nearest, String languageCode)
    : id = nearest.spot.id,
      name = nearest.spot.title,
      meta = [
        formatDistance(nearest.meters, languageCode),
        if (nearest.spot.ratingCount > 0)
          '★ ${formatRating(nearest.spot.ratingAvg)}',
      ].join(' · '),
      tags = SpotTag.sorted(nearest.spot.tags)
          .take(kWidgetTags)
          .map((t) => t.label(languageCode))
          .join(' · ');

  final int id;
  final String name;

  /// Distance, and the rating when the spot has one.
  final String meta;

  /// Empty when the spot has none.
  final String tags;

  @override
  Map<String, Object> toJson() => {
    'state': 'spot',
    'id': id,
    'name': name,
    'meta': meta,
    'tags': tags,
  };
}

/// Works out what the widget should show from what the app learns anyway:
/// position lookups and the spots the map loads for its viewport. No request
/// is made for the widget, so the position stays on the device.
///
/// The map only knows the spots around its viewport, so the closest one seen
/// for a position is kept: panning away, zooming out to a cut-off result or
/// filtering by tag does not replace it by one further off.
class NearestSpotTracker {
  NearestSpotTracker({required this.languageCode});

  /// Language of the texts in the payloads.
  final String Function() languageCode;

  LatLng? _position;
  List<Spot>? _spots;
  bool _spotsFiltered = false;
  SpotDistance? _best;

  /// A position lookup answered; [position] null when it failed.
  NearestSpotPayload? onLookup(LatLng? position) {
    if (position == null) {
      _position = null;
      _best = null;
      return const NoLocationPayload();
    }
    final last = _position;
    if (last == null || _distance(last, position) > kSamePlaceMeters) {
      _best = null;
    }
    _position = position;
    return _update();
  }

  /// The map finished loading [spots]; [filtered] when they are only those
  /// with certain tags.
  NearestSpotPayload? onSpots(List<Spot> spots, {required bool filtered}) {
    _spots = spots;
    _spotsFiltered = filtered;
    return _update();
  }

  NearestSpotPayload? _update() {
    final position = _position;
    final spots = _spots;
    if (position == null || spots == null) return null;
    final candidate = nearestSpot(position, spots);
    final best = _best;
    if (candidate != null && (best == null || candidate.meters < best.meters)) {
      _best = candidate;
    }
    final now = _best;
    if (now != null) return SpotPayload(now, languageCode());
    return _spotsFiltered ? null : const NoSpotsPayload();
  }
}
