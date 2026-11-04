import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/admin/admin_two_factor_card.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:app/router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

/// Admin routes want a session (or `totp_setup_required` when [setup]).
class _Server implements HttpClientAdapter {
  bool setup = false;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    paths.add(o.path);
    if (setup) {
      return _json(403, {
        'error': {'code': 'totp_setup_required', 'message': ''},
      });
    }
    if (o.path == '/admin/2fa/session') {
      return o.headers['X-TOTP'] == '123456'
          ? _json(200, {
              'token': 's1',
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 15))
                  .toIso8601String(),
            })
          : _json(403, {
              'error': {'code': 'totp_invalid', 'message': ''},
            });
    }
    if (o.headers['X-Admin-Session'] == 's1') return _json(200, {'ok': true});
    return _json(403, {
      'error': {'code': 'totp_required', 'message': ''},
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, _Server, GoRouter)> _pump(WidgetTester t) async {
  final server = _Server();
  final api = ApiClient(
    tokenStore: TokenStore.memory(),
    baseUrl: 'http://x/api/v1',
    adapter: server,
  );
  final router = GoRouter(
    navigatorKey: GlobalKey<NavigatorState>(),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold()),
      GoRoute(
        path: kAdminTwoFactorPath,
        builder: (_, _) => const Scaffold(body: Text('setup page')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        routerProvider.overrideWithValue(router),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(adminTwoFactorPromptsProvider);
          return MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        },
      ),
    ),
  );
  await t.pumpAndSettle();
  return (api, server, router);
}

void main() {
  testWidgets('a refused admin request asks on the root navigator', (t) async {
    final (api, server, _) = await _pump(t);
    Map<String, dynamic>? result;
    api.get<Map<String, dynamic>>('/admin/reports').then((r) => result = r);
    await t.pumpAndSettle();
    expect(find.text('Admin confirmation'), findsOneWidget);

    await t.enterText(find.byKey(const Key('admin-code-field')), '000000');
    await t.pump();
    await t.tap(find.byKey(const Key('admin-code-submit')));
    await t.pumpAndSettle();
    // asked again, with the error
    expect(find.text('Wrong code. Try again.'), findsOneWidget);

    await t.enterText(find.byKey(const Key('admin-code-field')), '123456');
    await t.pump();
    await t.tap(find.byKey(const Key('admin-code-submit')));
    await t.pumpAndSettle();
    expect(find.text('Admin confirmation'), findsNothing);
    expect(result, {'ok': true});
    expect(server.paths, [
      '/admin/reports',
      '/admin/2fa/session',
      '/admin/2fa/session',
      '/admin/reports',
    ]);
  });

  testWidgets('setup required opens the setup page once', (t) async {
    final (api, server, router) = await _pump(t);
    server.setup = true;
    final errors = <Object?>[];
    for (final p in ['/admin/reports', '/admin/users', '/admin/spots']) {
      api
          .get<Map<String, dynamic>>(p)
          .then<void>(errors.add, onError: errors.add);
    }
    await t.pumpAndSettle();

    expect(errors, hasLength(3));

    expect(
      errors.every((e) => e is ApiException && e.code == 'totp_setup_required'),
      isTrue,
    );
    expect(find.text('setup page'), findsOneWidget);
    expect(find.text('Admin confirmation'), findsNothing);
    // one page on top of home, not three
    expect(router.canPop(), isTrue);
    router.pop();
    await t.pumpAndSettle();
    expect(router.canPop(), isFalse);
  });
}
