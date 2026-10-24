import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart' show apiClientProvider;

class GeoResult {
  const GeoResult({required this.label, required this.lat, required this.lon});

  factory GeoResult.fromJson(Map<String, dynamic> j) => GeoResult(
    label: '${j['label']}',
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
  );

  final String label;
  final double lat;
  final double lon;
}

/// Address search via the backend (`GET /geocode?q=`). Results are already
/// restricted to DACH. Throws [ApiException] (`invalid_query`, `rate_limited`,
/// `geocoder_unavailable`, `geocoder_busy`).
abstract class GeocodeRepository {
  Future<List<GeoResult>> search(String query);
}

class ApiGeocodeRepository implements GeocodeRepository {
  ApiGeocodeRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<GeoResult>> search(String query) async {
    final body = await _api.get<Map<String, dynamic>>(
      '/geocode',
      query: {'q': query},
    );
    final list = (body['results'] as List?) ?? const [];
    return [
      for (final r in list) GeoResult.fromJson(Map<String, dynamic>.from(r)),
    ];
  }
}

final geocodeRepositoryProvider = Provider<GeocodeRepository>(
  (ref) => ApiGeocodeRepository(ref.watch(apiClientProvider)),
);
