import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../core/providers.dart' show apiClientProvider;

/// A user found by name, with the number of spots others can see.
class UserMatch {
  const UserMatch({required this.author, this.spotCount = 0});

  final Author author;
  final int spotCount;

  factory UserMatch.fromJson(Map<String, dynamic> j) => UserMatch(
    author: Author.fromJson(j),
    spotCount: (j['spot_count'] ?? 0) as int,
  );
}

/// Users by name (`GET /users/search`): at most 20, the best match first.
abstract class UserSearchRepository {
  Future<List<UserMatch>> search(String query);
}

class ApiUserSearchRepository implements UserSearchRepository {
  ApiUserSearchRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<UserMatch>> search(String query) async {
    final data = await _api.get<List<dynamic>>(
      '/users/search',
      query: {'q': query},
    );
    return [
      for (final e in data) UserMatch.fromJson(e as Map<String, dynamic>),
    ];
  }
}

final userSearchRepositoryProvider = Provider<UserSearchRepository>(
  (ref) => ApiUserSearchRepository(ref.watch(apiClientProvider)),
);
