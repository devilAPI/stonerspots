import 'dart:async';

import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/spots/photo_uploader.dart';
import 'package:app/features/spots/update_composer.dart';
import 'package:app/features/spots/updates_repository.dart';
import 'package:app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_helpers.dart';

late FakeUpdates updates;
late FakeUploader uploader;
late FakePicker picker;
bool? result;

Future<void> open(
  WidgetTester t, {
  Size size = const Size(400, 800),
  FeedItem? editing,
  List<String> files = const [],
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  updates = FakeUpdates();
  uploader = FakeUploader();
  picker = FakePicker([for (final f in files) fakeFile(f)]);
  result = null;
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        spotUpdatesRepositoryProvider.overrideWithValue(updates),
        photoUploaderProvider.overrideWithValue(uploader),
        photoPickerProvider.overrideWithValue(picker),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () async => result = await showUpdateComposer(
                c,
                spotId: 5,
                editing: editing,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

FilledButton submit(WidgetTester t) =>
    t.widget<FilledButton>(find.byKey(const Key('updateSubmit')));

bool tagSelected(WidgetTester t, String name) =>
    t.widget<ChoiceChip>(find.byKey(Key('updateTag_$name'))).selected;

Future<void> addPhotos(WidgetTester t) async {
  await t.tap(find.byKey(const Key('updateAddPhotos')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the Note tag and an empty, disabled form', (
    t,
  ) async {
    await open(t);
    expect(tagSelected(t, 'note'), isTrue);
    expect(tagSelected(t, 'crowded'), isFalse);
    for (final label in ['Note', 'Still good', 'Crowded', 'Dirty', 'Closed']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(submit(t).onPressed, isNull);
  });

  testWidgets('text enables submit and sends body with the chosen tag', (
    t,
  ) async {
    await open(t);
    await t.enterText(find.byKey(const Key('updateBody')), ' fresh air ');
    await t.pump();
    expect(submit(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('updateTag_stillGood')));
    await t.pump();
    expect(tagSelected(t, 'stillGood'), isTrue);
    expect(tagSelected(t, 'note'), isFalse);
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    expect(updates.posted.single.body, 'fresh air');
    expect(updates.posted.single.tag, UpdateTag.stillGood);
    expect(updates.posted.single.photoIds, isEmpty);
    expect(result, isTrue);
    expect(find.byKey(const Key('updateSubmit')), findsNothing);
  });

  testWidgets('a photo alone enables submit; whitespace alone does not', (
    t,
  ) async {
    await open(t, files: ['a.jpg']);
    await t.enterText(find.byKey(const Key('updateBody')), '   ');
    await t.pump();
    expect(submit(t).onPressed, isNull);
    await addPhotos(t);
    expect(submit(t).onPressed, isNotNull);
    await t.tap(find.byKey(const Key('updateRemovePhoto_0')));
    await t.pump();
    expect(find.byKey(const Key('updatePhoto_0')), findsNothing);
    expect(submit(t).onPressed, isNull);
  });

  testWidgets('at most four photos can be added', (t) async {
    await open(t, files: ['1', '2', '3', '4', '5', '6']);
    await addPhotos(t);
    expect(picker.requestedMax, [4]);
    for (var i = 0; i < 4; i++) {
      expect(find.byKey(Key('updatePhoto_$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('updatePhoto_4')), findsNothing);
    expect(
      t
          .widget<OutlinedButton>(find.byKey(const Key('updateAddPhotos')))
          .onPressed,
      isNull,
    );
    expect(find.text('4/4'), findsOneWidget);
  });

  testWidgets('uploads show progress and block submit', (t) async {
    await open(t, files: ['a.jpg']);
    await addPhotos(t);
    uploader.gate = Completer<void>();
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pump();
    await t.pump();
    final bar = t.widget<LinearProgressIndicator>(
      find.byKey(const Key('updateProgress_0')),
    );
    expect(bar.value, 0.5);
    expect(submit(t).onPressed, isNull);
    uploader.gate!.complete();
    await t.pumpAndSettle();
    expect(updates.posted.single.photoIds, [101]);
  });

  testWidgets('upload failure keeps state; retry skips uploaded photos', (
    t,
  ) async {
    await open(t, files: ['a.jpg', 'b.jpg']);
    uploader.failOnce.add('b.jpg');
    await t.enterText(find.byKey(const Key('updateBody')), 'hi');
    await addPhotos(t);
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('updatePhoto_1')), findsOneWidget);
    expect(find.text('hi'), findsOneWidget);
    expect(submit(t).onPressed, isNotNull);
    expect(updates.posted, isEmpty);
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    expect(uploader.uploads, ['a.jpg', 'b.jpg', 'b.jpg']);
    expect(updates.posted.single.photoIds, [101, 103]);
    expect(result, isTrue);
  });

  testWidgets('a failed post keeps uploaded ids for the retry', (t) async {
    await open(t, files: ['a.jpg']);
    updates.postError = ApiException(500, 'internal', 'x');
    await addPhotos(t);
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    updates.postError = null;
    await t.tap(find.byKey(const Key('updateSubmit')));
    await t.pumpAndSettle();
    expect(uploader.uploads, ['a.jpg']);
    expect(updates.posted.single.photoIds, [101]);
  });

  for (final c in {
    'invalid_photo': 'One of the photos is invalid',
    'invalid_body': 'The text is invalid or too long',
    'invalid_tag': 'Please choose a valid status',
    'whatever': 'Something went wrong',
  }.entries) {
    testWidgets('inline error for ${c.key}', (t) async {
      await open(t);
      updates.postError = ApiException(400, c.key, 'x');
      await t.enterText(find.byKey(const Key('updateBody')), 'hi');
      await t.pump();
      await t.tap(find.byKey(const Key('updateSubmit')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('updateError')),
          matching: find.text(c.value),
        ),
        findsOneWidget,
      );
      expect(result, isNull);
      expect(find.byKey(const Key('updateSubmit')), findsOneWidget);
    });
  }

  group('edit mode', () {
    final item = feedItem(
      body: 'old',
      tag: UpdateTag.crowded,
      photos: const [PhotoRef(id: 1, url: 'u', thumbUrl: 't')],
    );

    testWidgets('prefills, shows photos read-only, nothing to save yet', (
      t,
    ) async {
      await open(t, editing: item);
      expect(find.text('old'), findsOneWidget);
      expect(tagSelected(t, 'crowded'), isTrue);
      expect(find.byKey(const Key('updatePhoto_0')), findsOneWidget);
      expect(find.byKey(const Key('updateRemovePhoto_0')), findsNothing);
      expect(find.byKey(const Key('updateAddPhotos')), findsNothing);
      expect(submit(t).onPressed, isNull);
    });

    testWidgets('sends only the changed text', (t) async {
      await open(t, editing: item);
      await t.enterText(find.byKey(const Key('updateBody')), 'new');
      await t.pump();
      await t.tap(find.byKey(const Key('updateSubmit')));
      await t.pumpAndSettle();
      expect(updates.edits.single.id, item.id);
      expect(updates.edits.single.body, 'new');
      expect(updates.edits.single.tag, isNull);
      expect(result, isTrue);
    });

    testWidgets('sends only the changed tag', (t) async {
      await open(t, editing: item);
      await t.tap(find.byKey(const Key('updateTag_closed')));
      await t.pump();
      await t.tap(find.byKey(const Key('updateSubmit')));
      await t.pumpAndSettle();
      expect(updates.edits.single.body, isNull);
      expect(updates.edits.single.tag, UpdateTag.closed);
    });

    testWidgets('shows API errors inline', (t) async {
      await open(t, editing: item);
      updates.editError = ApiException(400, 'invalid_tag', 'x');
      await t.tap(find.byKey(const Key('updateTag_dirty')));
      await t.pump();
      await t.tap(find.byKey(const Key('updateSubmit')));
      await t.pumpAndSettle();
      expect(find.text('Please choose a valid status'), findsOneWidget);
    });
  });

  for (final size in const [Size(400, 800), Size(844, 390), Size(1100, 700)]) {
    testWidgets('lays out without overflow at $size', (t) async {
      await open(t, size: size, files: ['1', '2', '3', '4']);
      await addPhotos(t);
      await t.enterText(find.byKey(const Key('updateBody')), 'a\nb\nc\nd');
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('updateSubmit')), findsOneWidget);
      // the action stays reachable even on a short screen
      await t.ensureVisible(find.byKey(const Key('updateSubmit')));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('wide screens use a dialog, phones a bottom sheet', (t) async {
    await open(t, size: const Size(1100, 700));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('phones use a bottom sheet', (t) async {
    await open(t);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
