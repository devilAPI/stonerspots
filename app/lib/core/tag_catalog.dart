import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import 'providers.dart';

/// Reads the tag catalog.
abstract class TagRepository {
  Future<List<SpotTag>> list();
}

class ApiTagRepository implements TagRepository {
  ApiTagRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<SpotTag>> list() async => [
    for (final e in await _api.get<List<dynamic>>('/tags'))
      SpotTag.fromJson(e as Map<String, dynamic>),
  ];
}

final tagRepositoryProvider = Provider<TagRepository>(
  (ref) => ApiTagRepository(ref.watch(apiClientProvider)),
);

/// The tag catalog in canonical order. Starts with what [SpotTag.values]
/// holds (the built-in tags) and changes after [TagCatalog.load] or an admin
/// edit; widgets that list tags watch it so they rebuild.
final tagCatalogProvider = NotifierProvider<TagCatalog, List<SpotTag>>(
  TagCatalog.new,
);

class TagCatalog extends Notifier<List<SpotTag>> {
  @override
  List<SpotTag> build() => SpotTag.values;

  /// Fetches the catalog; on failure the current one stays.
  Future<void> load() async {
    try {
      replace(await ref.read(tagRepositoryProvider).list());
    } catch (_) {}
  }

  void replace(List<SpotTag> tags) {
    SpotTag.setCatalog(tags);
    state = SpotTag.values;
  }
}
