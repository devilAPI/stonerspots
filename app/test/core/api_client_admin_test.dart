import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app/core/api_client.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

ResponseBody _error(int status, String code) => _json(status, {
  'error': {'code': code, 'message': code},
});

/// The admin 2FA of backend/internal/auth/guard.go, in memory: `123456` is
/// the right code, `111111` one used already, `999999` hits the limit.
class _Server implements HttpClientAdapter {
  _Server(this.now);

  final DateTime Function() now;
  final List<RequestOptions> seen = [];
  final Set<String> sessions = {};
  bool setupRequired = false;
  int _issued = 0;

  /// Answers to these paths wait (once) until their completer completes.
  final Map<String, Completer<void>> holds = {};

  Iterable<RequestOptions> get sessionCalls =>
      seen.where((o) => o.path == '/admin/2fa/session');

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    seen.add(o);
    final hold = holds.remove(o.path);
    if (hold != null) await hold.future;
    final session = o.headers['X-Admin-Session'] as String?;
    final code = o.headers['X-TOTP'] as String?;
    if (setupRequired) return _error(403, 'totp_setup_required');
    if (session != null && sessions.contains(session)) {
      if (o.path == '/admin/2fa/session') return _error(403, 'totp_required');
      return _json(200, {'ok': true});
    }
    if (code == null) {
      return _error(
        403,
        session == null ? 'totp_required' : 'totp_session_expired',
      );
    }
    switch (code) {
      case '111111':
        return _error(403, 'totp_reused');
      case '999999':
        return _error(429, 'rate_limited');
      case '123456':
        break;
      default:
        return _error(403, 'totp_invalid');
    }
    if (o.path != '/admin/2fa/session') return _json(200, {'ok': true});
    final token = 's${++_issued}';
    sessions.add(token);
    return _json(200, {
      'token': token,
      'expires_at': now()
          .toUtc()
          .add(const Duration(minutes: 15))
          .toIso8601String(),
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late DateTime clock;
  late _Server server;
  late ApiClient api;
  late List<AdminCodeReason> asked;

  setUp(() async {
    clock = DateTime.utc(2026, 11, 4, 12);
    server = _Server(() => clock);
    final store = TokenStore.memory();
    await store.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
    api = ApiClient(
      tokenStore: store,
      baseUrl: 'http://x/api/v1',
      adapter: server,
      now: () => clock,
    );
    asked = [];
  });

  /// Answers the prompts with [codes] in turn (null: cancel).
  void answer(List<String?> codes) {
    var i = 0;
    api.onAdminCodeNeeded = (reason) async {
      asked.add(reason);
      if (reason == AdminCodeReason.rateLimited) return null;
      return i < codes.length ? codes[i++] : null;
    };
  }

  Matcher apiError(String code, {int status = 403}) => throwsA(
    isA<ApiException>()
        .having((e) => e.code, 'code', code)
        .having((e) => e.status, 'status', status),
  );

  test('sends X-Admin-Session while the session is valid', () async {
    answer([]);
    await api.openAdminSession('123456');
    expect(api.hasAdminSession, isTrue);
    final open = server.sessionCalls.single;
    expect(open.headers['X-TOTP'], '123456');
    expect(open.headers['Authorization'], 'Bearer a');

    await api.get<Map<String, dynamic>>('/admin/reports');
    await api.get<Map<String, dynamic>>('/spots');
    expect(server.seen[1].headers['X-Admin-Session'], 's1');
    expect(server.seen[2].headers['X-Admin-Session'], 's1');

    // Past its 15 minutes it is not sent any more.
    clock = clock.add(const Duration(minutes: 15));
    expect(api.hasAdminSession, isFalse);
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_required'),
    );
    expect(server.seen.last.headers.containsKey('X-Admin-Session'), isFalse);
  });

  test('totp_required asks for a code, opens a session and retries', () async {
    answer(['123456']);
    final res = await api.get<Map<String, dynamic>>('/admin/reports');

    expect(res['ok'], isTrue);
    expect(asked, [AdminCodeReason.required]);
    expect(server.seen.map((o) => o.path), [
      '/admin/reports',
      '/admin/2fa/session',
      '/admin/reports',
    ]);
    // the session call carries the code and never an old session
    expect(server.seen[1].headers['X-TOTP'], '123456');
    expect(server.seen[1].headers.containsKey('X-Admin-Session'), isFalse);
    expect(server.seen[2].headers['X-Admin-Session'], 's1');
    expect(server.seen[2].headers.containsKey('X-TOTP'), isFalse);
  });

  test('requests refused at the same time share one prompt', () async {
    final code = Completer<String?>();
    api.onAdminCodeNeeded = (reason) {
      asked.add(reason);
      return code.future;
    };
    final all = Future.wait([
      api.get<Map<String, dynamic>>('/admin/reports'),
      api.get<Map<String, dynamic>>('/admin/users'),
      api.delete<Map<String, dynamic>>('/comments/3'),
    ]);
    await pumpEventQueue();
    expect(asked, [AdminCodeReason.required]);

    code.complete('123456');
    final results = await all;
    expect(results.every((r) => r['ok'] == true), isTrue);
    expect(asked, hasLength(1));
    expect(server.sessionCalls, hasLength(1));
  });

  test('a request refused after a session was opened just retries', () async {
    answer([]);
    final hold = Completer<void>();
    server.holds['/admin/users'] = hold;
    final late = api.get<Map<String, dynamic>>('/admin/users'); // no session
    await pumpEventQueue();
    await api.openAdminSession('123456');
    hold.complete();

    expect((await late)['ok'], isTrue);
    expect(asked, isEmpty);
    expect(server.seen.last.headers['X-Admin-Session'], 's1');
  });

  test('cancel throws the original error', () async {
    answer([null]);
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_required'),
    );
    expect(asked, [AdminCodeReason.required]);
    expect(server.sessionCalls, isEmpty);
  });

  test('a wrong or used code asks again with the error', () async {
    answer(['000000', '111111', '123456']);
    final res = await api.get<Map<String, dynamic>>('/admin/reports');
    expect(res['ok'], isTrue);
    expect(asked, [
      AdminCodeReason.required,
      AdminCodeReason.invalid,
      AdminCodeReason.reused,
    ]);
  });

  test('gives up after a few wrong codes', () async {
    answer(['000000', '000001', '000002', '123456']);
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_invalid'),
    );
    expect(asked, hasLength(ApiClient.maxAdminCodeAttempts));
    expect(server.sessionCalls, hasLength(ApiClient.maxAdminCodeAttempts));
    expect(api.hasAdminSession, isFalse);
  });

  test('429 tells the admin to wait, then fails with it', () async {
    answer(['999999', '123456']);
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('rate_limited', status: 429),
    );
    expect(asked, [AdminCodeReason.required, AdminCodeReason.rateLimited]);
    expect(server.sessionCalls, hasLength(1));
  });

  test('a session the server no longer takes asks again as expired', () async {
    answer(['123456', '123456']);
    await api.openAdminSession('123456');
    server.sessions.clear(); // e.g. the server restarted with a new key

    final res = await api.get<Map<String, dynamic>>('/admin/reports');
    expect(res['ok'], isTrue);
    expect(asked, [AdminCodeReason.expired]);
    expect(server.seen.last.headers['X-Admin-Session'], 's2');
  });

  test('without a prompt the refusal is thrown as is', () async {
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_required'),
    );
    expect(server.seen, hasLength(1));
  });

  test('totp_setup_required leads to the setup, not to a prompt', () async {
    answer(['123456']);
    var setups = 0;
    api.onAdminSetupRequired = () => setups++;
    server.setupRequired = true;
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_setup_required'),
    );
    expect(setups, 1);
    expect(asked, isEmpty);
  });

  test('clearAdminSession stops sending it', () async {
    await api.openAdminSession('123456');
    api.clearAdminSession();
    expect(api.hasAdminSession, isFalse);
    await expectLater(
      api.get<Map<String, dynamic>>('/admin/reports'),
      apiError('totp_required'),
    );
    expect(server.seen.last.headers.containsKey('X-Admin-Session'), isFalse);
  });

  test('logout clears the admin session', () async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(api.tokenStore),
      ],
    );
    addTearDown(container.dispose);
    // no /me in this fake: start logged out, the tokens are still stored
    await api.tokenStore.clear();
    await container.read(authControllerProvider.future);
    await api.tokenStore.write(
      const Tokens(accessToken: 'a', refreshToken: 'r'),
    );
    await api.openAdminSession('123456');
    expect(api.hasAdminSession, isTrue);

    await container.read(authControllerProvider.notifier).logout();
    expect(api.hasAdminSession, isFalse);
  });
}
