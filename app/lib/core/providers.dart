import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>(
    (ref) => ApiClient(tokenStore: ref.watch(tokenStoreProvider)));

// Placeholders. Tasks 8, 9 and 10 each replace the body of the one they own
// with the real repository (the type of each provider is `Object` until then;
// the owning task changes it to its repository type).
final spotsRepositoryProvider =
    Provider<Object>((ref) => throw UnimplementedError('spotsRepositoryProvider'));

final feedRepositoryProvider =
    Provider<Object>((ref) => throw UnimplementedError('feedRepositoryProvider'));

final updatesRepositoryProvider = Provider<Object>(
    (ref) => throw UnimplementedError('updatesRepositoryProvider'));
