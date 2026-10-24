import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart';

abstract class SpotsRepository {
  Future<List<Spot>> inBounds(LatLngBounds bounds, {String? category});
}

class ApiSpotsRepository implements SpotsRepository {
  ApiSpotsRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<Spot>> inBounds(LatLngBounds bounds, {String? category}) async {
    final data = await _api.get<List<dynamic>>('/spots', query: {
      'south': bounds.south,
      'west': bounds.west,
      'north': bounds.north,
      'east': bounds.east,
      'category': ?category,
      'limit': 50,
    });
    return data
        .map((e) => Spot.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

/// Typed provider for the map feature (the placeholder in core/providers.dart
/// is untyped).
final mapSpotsRepositoryProvider = Provider<SpotsRepository>(
    (ref) => ApiSpotsRepository(ref.watch(apiClientProvider)));
