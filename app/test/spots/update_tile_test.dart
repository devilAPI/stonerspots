import 'package:app/core/models.dart';
import 'package:app/features/spots/update_tile.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_helpers.dart';

Future<List<String>> pump(
  WidgetTester t,
  FeedItem item, {
  required bool mine,
}) async {
  final events = <String>[];
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: UpdateTile(
            item: item,
            isMine: mine,
            onEdit: () => events.add('edit'),
            onDelete: () => events.add('delete'),
            onReport: () => events.add('report'),
            onPhotoTap: (i) => events.add('photo$i'),
          ),
        ),
      ),
    ),
  );
  return events;
}

const photos = [
  PhotoRef(id: 1, url: 'u1', thumbUrl: 't1'),
  PhotoRef(id: 2, url: 'u2', thumbUrl: 't2'),
];

void main() {
  testWidgets('own update has edit and delete, no report', (t) async {
    final events = await pump(t, feedItem(), mine: true);
    expect(find.byKey(const Key('updateEdit_7')), findsOneWidget);
    expect(find.byKey(const Key('updateDelete_7')), findsOneWidget);
    expect(find.byKey(const Key('updateReport_7')), findsNothing);
    await t.tap(find.byKey(const Key('updateEdit_7')));
    await t.tap(find.byKey(const Key('updateDelete_7')));
    expect(events, ['edit', 'delete']);
  });

  testWidgets('foreign update only has report', (t) async {
    final events = await pump(t, feedItem(), mine: false);
    expect(find.byKey(const Key('updateEdit_7')), findsNothing);
    expect(find.byKey(const Key('updateDelete_7')), findsNothing);
    await t.tap(find.byKey(const Key('updateReport_7')));
    expect(events, ['report']);
  });

  testWidgets('shows author, relative time, body; hides the note tag', (
    t,
  ) async {
    await pump(t, feedItem(body: 'bench is dry'), mine: false);
    expect(find.textContaining('Ann'), findsOneWidget);
    expect(find.textContaining('3h'), findsOneWidget);
    expect(find.text('bench is dry'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
    expect(find.textContaining('edited'), findsNothing);
  });

  testWidgets('non-note tags show a chip; edited hint is shown', (t) async {
    await pump(
      t,
      feedItem(tag: UpdateTag.crowded, editedAt: DateTime.now()),
      mine: false,
    );
    expect(find.widgetWithText(Chip, 'Crowded'), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);
  });

  testWidgets('photo thumbnails report the tapped index', (t) async {
    final events = await pump(t, feedItem(photos: photos), mine: false);
    expect(find.byKey(const Key('updateTilePhoto_0')), findsOneWidget);
    await t.tap(find.byKey(const Key('updateTilePhoto_1')));
    expect(events, ['photo1']);
  });
}
