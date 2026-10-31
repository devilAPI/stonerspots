import 'package:app/core/models.dart';
import 'package:app/features/map/spot_preview_sheet.dart';
import 'package:app/features/map/spot_pull_sheet.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const spot = Spot(id: 1, title: 'Lake bench', lat: 48.1, lon: 11.6);

/// Opens the sheet over a page; returns how often it was fully pulled up.
Future<List<int>> openSheet(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final expanded = <int>[];
  await t.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('open'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              enableDrag: false,
              builder: (_) => SpotPullSheet(
                spot: spot,
                page: const Text('the page'),
                onOpen: () {},
                onExpanded: () {
                  expanded.add(1);
                  Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      transitionDuration: Duration.zero,
                      pageBuilder: (_, _, _) => const Text('real page'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return expanded;
}

void main() {
  testWidgets('a short pull springs back to the card', (t) async {
    final expanded = await openSheet(t);
    await t.drag(find.text('Lake bench'), const Offset(0, -40));
    await t.pumpAndSettle();
    expect(expanded, isEmpty);
    expect(find.byType(SpotPreviewSheet), findsOneWidget);
  });

  testWidgets('pulled up, the page takes over and the sheet is gone', (
    t,
  ) async {
    final expanded = await openSheet(t);
    await t.fling(find.text('Lake bench'), const Offset(0, -500), 1500);
    await t.pumpAndSettle();
    expect(expanded, hasLength(1));
    expect(find.text('real page'), findsOneWidget);
    expect(find.byType(SpotPullSheet), findsNothing);
  });

  testWidgets('pulled down, the sheet closes', (t) async {
    final expanded = await openSheet(t);
    await t.fling(find.text('Lake bench'), const Offset(0, 300), 1500);
    await t.pumpAndSettle();
    expect(expanded, isEmpty);
    expect(find.byType(SpotPullSheet), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
