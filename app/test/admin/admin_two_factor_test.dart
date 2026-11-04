import 'dart:convert';

import 'package:app/core/api_client.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/admin/admin_two_factor.dart';
import 'package:app/features/admin/admin_two_factor_card.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP';
const _uri =
    'otpauth://totp/Stonerspots:admin%40x?issuer=Stonerspots&secret=$_secret';

ApiException _err(String code, {int status = 403}) =>
    ApiException(status, code, code);

class _FakeTwoFactor implements TwoFactorRepository {
  _FakeTwoFactor({this.on = false});

  bool on;
  Object? statusError;
  final List<Object> verifyErrors = [];
  final List<Object> disableErrors = [];
  final calls = <String>[];

  @override
  Future<bool> enabled() async {
    calls.add('status');
    if (statusError != null) throw statusError!;
    return on;
  }

  @override
  Future<TwoFactorEnrollment> start() async {
    calls.add('start');
    return const TwoFactorEnrollment(secret: _secret, uri: _uri);
  }

  @override
  Future<void> verify(String code) async {
    calls.add('verify:$code');
    if (verifyErrors.isNotEmpty) throw verifyErrors.removeAt(0);
    on = true;
  }

  @override
  Future<void> disable({required String password, required String code}) async {
    calls.add('disable:$password:$code');
    if (disableErrors.isNotEmpty) throw disableErrors.removeAt(0);
    on = false;
  }
}

Future<void> _pump(WidgetTester t, _FakeTwoFactor repo) async {
  t.view.physicalSize = const Size(500, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [twoFactorRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AdminTwoFactorScreen(),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

String _status(WidgetTester t) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(const Key('totp-status')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('setup: secret and QR code, a wrong code, then on', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = _FakeTwoFactor()..verifyErrors.add(_err('totp_invalid'));
    await _pump(t, repo);
    expect(_status(t), 'Off');
    expect(find.textContaining('authenticator app'), findsOneWidget);

    await _tap(t, 'totp-enable');
    expect(repo.calls, ['status', 'start']);
    expect(find.byKey(const Key('totp-qr')), findsOneWidget);
    expect(
      find.text('JBSW Y3DP EHPK 3PXP JBSW Y3DP EHPK 3PXP'),
      findsOneWidget,
    );

    await _tap(t, 'totp-copy');
    expect(copied, _secret);
    expect(find.text('Key copied'), findsOneWidget);

    // too short: said inline, nothing sent
    await t.enterText(find.byKey(const Key('totp-code')), '123');
    await _tap(t, 'totp-verify');
    expect(find.text('The code has 6 digits.'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('verify')), isEmpty);

    await t.enterText(find.byKey(const Key('totp-code')), '000000');
    await _tap(t, 'totp-verify');
    expect(find.text('Wrong code. Try again.'), findsOneWidget);
    expect(find.byKey(const Key('totp-qr')), findsOneWidget);

    await t.enterText(find.byKey(const Key('totp-code')), '123456');
    await t.testTextInput.receiveAction(TextInputAction.done); // Enter
    await t.pumpAndSettle();
    expect(repo.calls.last, 'verify:123456');
    expect(find.byKey(const Key('totp-qr')), findsNothing);
    expect(_status(t), 'On');
    expect(find.byKey(const Key('totp-enabled-info')), findsOneWidget);
    expect(
      find.textContaining('asks for a code on every admin action'),
      findsOneWidget,
    );
  });

  testWidgets('setup can be cancelled', (t) async {
    final repo = _FakeTwoFactor();
    await _pump(t, repo);
    await _tap(t, 'totp-enable');
    await _tap(t, 'totp-cancel');
    expect(find.byKey(const Key('totp-qr')), findsNothing);
    expect(_status(t), 'Off');
  });

  testWidgets('turning off asks for password and code; errors inline', (
    t,
  ) async {
    final repo = _FakeTwoFactor(on: true)
      ..disableErrors.addAll([_err('wrong_password'), _err('totp_reused')]);
    await _pump(t, repo);
    expect(_status(t), 'On');
    expect(find.textContaining('need a code'), findsOneWidget);

    await _tap(t, 'totp-disable');
    await t.enterText(find.byKey(const Key('totp-disable-password')), 'pw');
    await t.enterText(find.byKey(const Key('totp-disable-code')), '123456');
    await _tap(t, 'totp-disable-submit');
    expect(find.text('Wrong password'), findsOneWidget);

    await _tap(t, 'totp-disable-submit');
    expect(find.textContaining('used already'), findsOneWidget);

    await _tap(t, 'totp-disable-submit');
    expect(repo.calls.where((c) => c.startsWith('disable')), [
      'disable:pw:123456',
      'disable:pw:123456',
      'disable:pw:123456',
    ]);
    expect(find.byKey(const Key('totp-disable-submit')), findsNothing);
    expect(find.text('2FA is off.'), findsOneWidget);
    expect(_status(t), 'Off');
  });

  testWidgets('a status refused for want of a code means 2FA is on', (t) async {
    final repo = _FakeTwoFactor()..statusError = _err('totp_required');
    await _pump(t, repo);
    expect(_status(t), 'On');
  });

  testWidgets('a failed status load can be retried', (t) async {
    final repo = _FakeTwoFactor()..statusError = _err('network_error');
    await _pump(t, repo);
    expect(find.byKey(const Key('totp-status')), findsNothing);
    repo.statusError = null;
    await _tap(t, 'totp-retry');
    expect(_status(t), 'Off');
  });

  test('disable opens a session with the code, then sends both', () async {
    final seen = <RequestOptions>[];
    final store = TokenStore.memory();
    await store.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
    final api = ApiClient(
      tokenStore: store,
      baseUrl: 'http://x/api/v1',
      adapter: _Adapter((o) {
        seen.add(o);
        if (o.path == '/admin/2fa/session') {
          return _json(200, {
            'token': 'sess',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 15))
                .toIso8601String(),
          });
        }
        return ResponseBody.fromString('', 204);
      }),
    );
    await ApiTwoFactorRepository(api).disable(password: 'pw', code: '123456');

    expect(seen.map((o) => o.path), [
      '/admin/2fa/session',
      '/admin/2fa/disable',
    ]);
    expect(seen[0].headers['X-TOTP'], '123456');
    expect(seen[1].headers['X-Admin-Session'], 'sess');
    expect(seen[1].data, {'password': 'pw', 'code': '123456'});
    expect(api.hasAdminSession, isFalse);
  });

  test('status, enable and verify use the documented routes', () async {
    final seen = <RequestOptions>[];
    final api = ApiClient(
      tokenStore: TokenStore.memory(),
      baseUrl: 'http://x/api/v1',
      adapter: _Adapter((o) {
        seen.add(o);
        return switch (o.path) {
          '/admin/2fa' => _json(200, {'enabled': true}),
          '/admin/2fa/enable' => _json(200, {'secret': _secret, 'uri': _uri}),
          _ => ResponseBody.fromString('', 204),
        };
      }),
    );
    final repo = ApiTwoFactorRepository(api);
    expect(await repo.enabled(), isTrue);
    final e = await repo.start();
    expect((e.secret, e.uri), (_secret, _uri));
    await repo.verify('123456');
    expect(seen.map((o) => '${o.method} ${o.path}'), [
      'GET /admin/2fa',
      'POST /admin/2fa/enable',
      'POST /admin/2fa/verify',
    ]);
    expect(seen.last.data, {'code': '123456'});
  });
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final ResponseBody Function(RequestOptions) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async => handler(o);

  @override
  void close({bool force = false}) {}
}
