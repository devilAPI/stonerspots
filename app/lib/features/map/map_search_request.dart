import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks the map to open its spot search (the search button beside the
/// tabs). The map listens; each [MapSearchRequest.open] counts up.
final mapSearchRequestProvider = NotifierProvider<MapSearchRequest, int>(
  MapSearchRequest.new,
);

class MapSearchRequest extends Notifier<int> {
  @override
  int build() => 0;

  void open() => state++;
}
