import 'package:app/core/api_client.dart';
import 'package:app/core/models.dart';
import 'package:app/features/map/spot_preview_sheet.dart';
import 'package:app/features/map/spot_pull_sheet.dart';
import 'package:app/features/saved/save_spot_button.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'saved_helpers.dart';

const _save = Key('saveSpot');

Future<void> _pump(
  WidgetTester t,
  FakeSaved repo, {
  User? user = kUser,
  bool iconOnly = false,
}) => pumpSaved(
  t,
  repo,
  user: user,
  initial: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(
        body: Center(child: SaveSpotButton(spotId: 5, iconOnly: iconOnly)),
      ),
    ),
  ],
);

/// Lets the notice's timer run out.
Future<void> _settleNotice(WidgetTester t) async {
  await t.pump(kSavedNoticeDuration);
  await t.pumpAndSettle();
}

const _rainy = SpotList(id: 2, name: 'Rainy days');

FakeSaved _twoLists({Map<int, Set<int>>? items}) => FakeSaved(
  lists: [
    const SpotList(id: kFavourites, name: 'Favourites', isDefault: true),
    _rainy,
  ],
  items: items,
);

void main() {
  testWidgets('logged out: goes to login and saves nothing', (t) async {
    final repo = FakeSaved();
    await _pump(t, repo, user: null);
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
    expect(repo.calls, isEmpty);
  });

  testWidgets('logged out: a long press goes to login too', (t) async {
    final repo = FakeSaved();
    await _pump(t, repo, user: null);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('a tap saves to Favourites at once and offers to change', (
    t,
  ) async {
    final repo = FakeSaved();
    await _pump(t, repo);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await t.tap(find.byKey(_save));
    await t.pump();
    await t.pump();
    expect(repo.calls, contains('favourite:5'));
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('Saved to Favourites'), findsOneWidget);
    expect(find.text('Change list'), findsOneWidget);
    await t.pumpAndSettle();
    await _settleNotice(t);
  });

  testWidgets('the snackbar goes away by itself, even with its action', (
    t,
  ) async {
    await _pump(t, FakeSaved());
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    await t.pump(kSavedNoticeDuration);
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('"change list" opens the sheet', (t) async {
    await _pump(t, _twoLists());
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    await t.tap(find.text('Change list'));
    await t.pumpAndSettle();
    expect(find.text('Save to lists'), findsOneWidget);
    final fav = t.widget<CheckboxListTile>(
      find.byKey(const Key('listCheck-$kFavourites')),
    );
    expect(fav.value, isTrue);
    await _settleNotice(t);
  });

  testWidgets('a spot in any list shows filled, and a tap opens the sheet', (
    t,
  ) async {
    final repo = _twoLists(
      items: {
        2: {5},
      },
    );
    await _pump(t, repo);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.text('Save to lists'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('favourite')), isEmpty);
  });

  testWidgets('a long press opens the sheet without saving', (t) async {
    final repo = _twoLists();
    await _pump(t, repo);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.text('Save to lists'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Rainy days'), findsOneWidget);
    expect(find.text('New list'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('favourite')), isEmpty);
  });

  testWidgets('checkboxes add and remove, and drive the bookmark', (t) async {
    final repo = _twoLists();
    await _pump(t, repo);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('listCheck-2')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('add:2:5'));
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('listCheck-2'))).value,
      isTrue,
    );

    await t.tap(find.byKey(const Key('listCheck-2')));
    await t.pumpAndSettle();
    expect(repo.calls, contains('remove:2:5'));
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('listCheck-2'))).value,
      isFalse,
    );

    Navigator.of(t.element(find.text('Save to lists'))).pop();
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('a failed change is undone and said in the sheet', (t) async {
    final repo = _twoLists();
    await _pump(t, repo);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();
    repo.failWrites = Exception('down');
    await t.tap(find.byKey(const Key('listCheck-2')));
    await t.pumpAndSettle();
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('listCheck-2'))).value,
      isFalse,
    );
    expect(find.byKey(const Key('saveSheetError')), findsOneWidget);
  });

  testWidgets('"New list" creates it and puts the spot in', (t) async {
    final repo = _twoLists();
    await _pump(t, repo);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sheetNewList')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('listName')), ' By the river ');
    await t.pump();
    await t.tap(find.byKey(const Key('listNameSave')));
    await t.pumpAndSettle();
    expect(repo.calls, containsAllInOrder(['create:By the river', 'add:10:5']));
    expect(find.text('By the river'), findsOneWidget);
    expect(
      t.widget<CheckboxListTile>(find.byKey(const Key('listCheck-10'))).value,
      isTrue,
    );
  });

  testWidgets('a full account gets told so', (t) async {
    final repo = _twoLists();
    await _pump(t, repo);
    await t.longPress(find.byKey(_save));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('sheetNewList')));
    await t.pumpAndSettle();
    repo.failWrites = ApiException(409, 'list_limit', 'x');
    await t.enterText(find.byKey(const Key('listName')), 'One more');
    await t.pump();
    await t.tap(find.byKey(const Key('listNameSave')));
    await t.pumpAndSettle();
    expect(
      find.text('You have reached the maximum number of lists'),
      findsOneWidget,
    );
  });

  testWidgets('a failed save stays unsaved and says so', (t) async {
    final repo = FakeSaved()..failWrites = Exception('down');
    await _pump(t, repo);
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await _settleNotice(t);
  });

  testWidgets('a spot whose lists cannot be read can still be saved', (
    t,
  ) async {
    final repo = _FailingMembership();
    await _pump(t, repo);
    await t.tap(find.byKey(_save));
    await t.pumpAndSettle();
    expect(repo.calls, contains('favourite:5'));
    await _settleNotice(t);
  });

  group('in the map card', () {
    const spot = Spot(id: 5, title: 'Lake bench', lat: 48.1, lon: 11.6);

    /// The card as the map opens it: in a modal sheet of the root navigator,
    /// so without a Scaffold of its own.
    Future<void> openCard(WidgetTester t, FakeSaved repo, {User? user}) async {
      portrait(t);
      await pumpSaved(
        t,
        repo,
        user: user,
        initial: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                child: const Text('open'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  useRootNavigator: true,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  enableDrag: false,
                  builder: (_) => SpotPullSheet(
                    spot: spot,
                    page: const SizedBox(),
                    onOpen: () {},
                    onExpanded: () {},
                  ),
                ),
              ),
            ),
          ),
        ],
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.byType(SpotPreviewSheet), findsOneWidget);
    }

    testWidgets('the notice shows above the card, not behind it', (t) async {
      final repo = _twoLists();
      await openCard(t, repo, user: kUser);
      await t.tap(find.byKey(_save));
      await t.pump();
      await t.pump();
      expect(repo.calls, contains('favourite:5'));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('savedNotice')), findsOneWidget);
      // something that can be hit is really on top
      t.element(find.text('Change list'));
      await t.tap(find.text('Change list'));
      await t.pumpAndSettle();
      expect(find.text('Save to lists'), findsOneWidget);
      expect(find.byKey(const Key('savedNotice')), findsNothing);
    });

    testWidgets('the notice leaves by itself', (t) async {
      await openCard(t, _twoLists(), user: kUser);
      await t.tap(find.byKey(_save));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('savedNotice')), findsOneWidget);
      await _settleNotice(t);
      expect(find.byKey(const Key('savedNotice')), findsNothing);
    });

    testWidgets('logged out it goes to login, and the card stays', (t) async {
      final repo = _twoLists();
      await openCard(t, repo);
      await t.tap(find.byKey(_save));
      await t.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });
  });
}

class _FailingMembership extends FakeSaved {
  @override
  Future<Set<int>> membership(int spotId) async => throw Exception('down');
}
