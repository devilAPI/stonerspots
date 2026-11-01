import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/providers.dart' show apiClientProvider;
import '../../l10n/app_localizations.dart';

/// One of the user's private lists of saved spots.
class SpotList {
  const SpotList({
    required this.id,
    required this.name,
    this.isDefault = false,
    this.spotCount = 0,
    this.coverUrl,
  });

  final int id;
  final String name;

  /// The Favourites list: always there, fixed, and shown translated.
  final bool isDefault;
  final int spotCount;
  final String? coverUrl;

  String title(AppLocalizations l) => isDefault ? l.savedFavourites : name;

  factory SpotList.fromJson(Map<String, dynamic> j) {
    final cover = (j['cover_url'] ?? '') as String;
    return SpotList(
      id: j['id'] as int,
      name: (j['name'] ?? '') as String,
      isDefault: (j['is_default'] ?? false) as bool,
      spotCount: (j['spot_count'] ?? 0) as int,
      coverUrl: cover.trim().isEmpty ? null : cover,
    );
  }
}

abstract class SavedRepository {
  /// The default list first.
  Future<List<SpotList>> lists();
  Future<SpotList> getList(int id);

  /// Throws [ApiException] with code `name_taken` or `list_limit`.
  Future<SpotList> create(String name);

  /// Throws [ApiException] with code `name_taken`.
  Future<SpotList> rename(int id, String name);
  Future<void> deleteList(int id);

  /// Most recently saved first.
  Future<CursorPage<Spot>> spots(int listId, {String? cursor});

  /// The ids of the user's lists holding the spot. The writes below answer
  /// with the same.
  Future<Set<int>> membership(int spotId);
  Future<Set<int>> saveToFavourites(int spotId);
  Future<Set<int>> addSpot(int listId, int spotId);
  Future<Set<int>> removeSpot(int listId, int spotId);
}

Set<int> _ids(Map<String, dynamic> json) =>
    ((json['list_ids'] ?? const []) as List).cast<int>().toSet();

class ApiSavedRepository implements SavedRepository {
  ApiSavedRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<SpotList>> lists() async {
    final json = await _api.get<Map<String, dynamic>>('/lists');
    return ((json['items'] ?? const []) as List)
        .map((e) => SpotList.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SpotList> getList(int id) async =>
      SpotList.fromJson(await _api.get<Map<String, dynamic>>('/lists/$id'));

  @override
  Future<SpotList> create(String name) async => SpotList.fromJson(
    await _api.post<Map<String, dynamic>>('/lists', data: {'name': name}),
  );

  @override
  Future<SpotList> rename(int id, String name) async => SpotList.fromJson(
    await _api.patch<Map<String, dynamic>>('/lists/$id', data: {'name': name}),
  );

  @override
  Future<void> deleteList(int id) async {
    await _api.delete<dynamic>('/lists/$id');
  }

  @override
  Future<CursorPage<Spot>> spots(int listId, {String? cursor}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/lists/$listId/spots',
      query: {'limit': 20, 'cursor': ?cursor},
    );
    return CursorPage.fromJson(json, Spot.fromJson);
  }

  @override
  Future<Set<int>> membership(int spotId) async =>
      _ids(await _api.get<Map<String, dynamic>>('/spots/$spotId/lists'));

  @override
  Future<Set<int>> saveToFavourites(int spotId) async => _ids(
    await _api.put<Map<String, dynamic>>('/lists/default/spots/$spotId'),
  );

  @override
  Future<Set<int>> addSpot(int listId, int spotId) async => _ids(
    await _api.put<Map<String, dynamic>>('/lists/$listId/spots/$spotId'),
  );

  @override
  Future<Set<int>> removeSpot(int listId, int spotId) async => _ids(
    await _api.delete<Map<String, dynamic>>('/lists/$listId/spots/$spotId'),
  );
}

final savedRepositoryProvider = Provider<SavedRepository>(
  (ref) => ApiSavedRepository(ref.watch(apiClientProvider)),
);
