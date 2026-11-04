import 'dart:convert';
import 'dart:io';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/core/providers.dart';
import 'package:app/core/token_store.dart';
import 'package:app/features/auth/auth_controller.dart';
import 'package:app/features/auth/auth_repository.dart';
import 'package:app/features/auth/profile_screen.dart';
import 'package:app/features/legal/data_export.dart';
import 'package:app/features/legal/export_saver_io.dart';
import 'package:app/features/users/users_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../users/users_helpers.dart' show FakeUsers;
import 'legal_helpers.dart';

class _Auth implements AuthRepository {
  @override
  Future<User?> me() async =>
      const User(id: 1, email: 'a@b.ch', displayName: 'Alex');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Export implements DataExportRepository {
  _Export({this.error});
  final Object? error;
  int calls = 0;

  @override
  Future<String> fetch() async {
    calls++;
    if (error != null) throw error!;
    return '{"format": "stonerspots-export/1"}\n';
  }
}

class FakeSaver {
  FakeSaver(this.result);
  final ExportResult result;
  final saved = <(String, String)>[];

  Future<ExportResult> call(String name, String content) async {
    saved.add((name, content));
    return result;
  }
}

Future<void> pumpProfile(
  WidgetTester t, {
  required DataExportRepository repo,
  required FakeSaver saver,
  String lang = 'en',
}) async {
  t.view.physicalSize = const Size(900, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final tokens = TokenStore.memory();
  await tokens.write(const Tokens(accessToken: 'a', refreshToken: 'r'));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_Auth()),
        tokenStoreProvider.overrideWithValue(tokens),
        dataExportRepositoryProvider.overrideWithValue(repo),
        exportSaverProvider.overrideWithValue(saver.call),
        usersRepositoryProvider.overrideWithValue(
          FakeUsers(
            profiles: {
              1: UserProfile(
                id: 1,
                displayName: 'Alex',
                createdAt: DateTime.utc(2025),
                isMe: true,
              ),
            },
          ),
        ),
      ],
      child: MaterialApp.router(
        locale: Locale(lang),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
          ],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> exportFromMenu(WidgetTester t) async {
  await t.tap(find.byKey(const Key('account-menu')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const Key('export-data')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the account menu downloads the data and says where', (t) async {
    final repo = _Export();
    final saver = FakeSaver(const ExportSaved('/home/a/Downloads/x.json'));
    await pumpProfile(t, repo: repo, saver: saver);
    await t.tap(find.byKey(const Key('account-menu')));
    await t.pumpAndSettle();
    expect(find.text('Download my data'), findsOneWidget);
    await t.tap(find.byKey(const Key('export-data')));
    await t.pumpAndSettle();

    expect(repo.calls, 1);
    final (name, content) = saver.saved.single;
    expect(
      name,
      matches(RegExp(r'^stonerspots-export-\d{4}-\d\d-\d\d\.json$')),
    );
    expect(content, contains('stonerspots-export/1'));
    expect(find.text('Saved to /home/a/Downloads/x.json'), findsOneWidget);
  });

  testWidgets('web: the browser download, in German', (t) async {
    final saver = FakeSaver(const ExportDownloaded('stonerspots-export.json'));
    await pumpProfile(t, repo: _Export(), saver: saver, lang: 'de');
    await t.tap(find.byKey(const Key('account-menu')));
    await t.pumpAndSettle();
    expect(find.text('Meine Daten herunterladen'), findsOneWidget);
    await t.tap(find.byKey(const Key('export-data')));
    await t.pumpAndSettle();
    expect(
      find.text('Download gestartet: stonerspots-export.json'),
      findsOneWidget,
    );
  });

  testWidgets('share sheet: no extra message', (t) async {
    final saver = FakeSaver(const ExportShared());
    await pumpProfile(t, repo: _Export(), saver: saver);
    await exportFromMenu(t);
    expect(saver.saved, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('too many downloads today', (t) async {
    final saver = FakeSaver(const ExportShared());
    await pumpProfile(
      t,
      repo: _Export(error: ApiException(429, 'rate_limited', '')),
      saver: saver,
    );
    await exportFromMenu(t);
    expect(saver.saved, isEmpty);
    expect(find.textContaining('at most three times a day'), findsOneWidget);
  });

  testWidgets('other failures', (t) async {
    final saver = FakeSaver(const ExportShared());
    await pumpProfile(
      t,
      repo: _Export(error: ApiException(0, 'network_error', '')),
      saver: saver,
    );
    await exportFromMenu(t);
    expect(
      find.text('That did not work. Please try again later.'),
      findsOneWidget,
    );
  });

  test('ApiDataExportRepository: GET /me/export, pretty JSON', () async {
    final a = JsonAdapter(
      (_) => (
        200,
        {
          'format': 'stonerspots-export/1',
          'profile': {'email': 'a@b.ch'},
        },
      ),
    );
    final tokens = TokenStore.memory();
    await tokens.write(const Tokens(accessToken: 'tok', refreshToken: 'r'));
    final json = await ApiDataExportRepository(
      ApiClient(tokenStore: tokens, baseUrl: 'http://x/api/v1', adapter: a),
    ).fetch();
    final req = a.seen.single;
    expect(req.method, 'GET');
    expect(req.uri.path, '/api/v1/me/export');
    expect(req.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(json)['profile']['email'], 'a@b.ch');
    expect(json, contains('\n  "profile"'));
  });

  test('file names', () {
    expect(
      exportFileName(DateTime(2026, 3, 7)),
      'stonerspots-export-2026-03-07.json',
    );
    final dir = Directory.systemTemp.createTempSync('export_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = freeFile(dir, 'e.json');
    expect(first.path, endsWith('${Platform.pathSeparator}e.json'));
    first.writeAsStringSync('1');
    final second = freeFile(dir, 'e.json');
    expect(second.path, endsWith('${Platform.pathSeparator}e-2.json'));
    second.writeAsStringSync('2');
    expect(freeFile(dir, 'e.json').path, endsWith('e-3.json'));
  });
}
