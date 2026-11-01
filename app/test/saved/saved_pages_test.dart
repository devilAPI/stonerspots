import 'package:app/core/api_client.dart';
import 'package:app/core/glass.dart';
import 'package:app/features/feed/satellite_thumb.dart';
import 'package:app/features/saved/saved_list_screen.dart';
import 'package:app/features/saved/saved_lists_screen.dart';
import 'package:app/features/saved/saved_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'saved_helpers.dart';

final _routes = <RouteBase>[
  GoRoute(path: '/saved', builder: (_, _) => const SavedListsScreen()),
  GoRoute(
    path: '/saved/:id',
    builder: (_, s) =>
        SavedListScreen(listId: int.parse(s.pathParameters['id']!)),
  ),
];

const _rainy = SpotList(id: 2, name: 'Rainy days');

FakeSaved _repo({Map<int, Set<int>>? items}) => FakeSaved(
  lists: [
    const SpotList(id: kFavourites, name: 'Favourites', isDefault: true),
    _rainy,
  ],
  items: items,
);

Future<GoRouter> _lists(
  WidgetTester t,
  FakeSaved repo, {
  Locale locale = const Locale('en'),
}) => pumpSaved(t, repo, routes: _routes, initial: '/saved', locale: locale);

/// With a page below, so the list can leave to it.
Future<GoRouter> _list(WidgetTester t, FakeSaved repo, int id) async {
  final router = await _lists(t, repo);
  router.push('/saved/$id');
  await t.pumpAndSettle();
  return router;
}

void main() {
  group('lists page', () {
    testWidgets('shows name, count and cover placeholder', (t) async {
      await _lists(
        t,
        _repo(
          items: {
            kFavourites: {5, 6},
          },
        ),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.text('2 spots'), findsOneWidget);
      expect(find.text('Rainy days'), findsOneWidget);
      expect(find.text('No spots'), findsOneWidget);
    });

    testWidgets('names the default list in the app language', (t) async {
      await _lists(t, _repo(), locale: const Locale('de'));
      expect(find.text('Favoriten'), findsOneWidget);
      expect(find.text('Favourites'), findsNothing);
      expect(find.text('Gespeichert'), findsOneWidget);
    });

    testWidgets('only own lists have a menu', (t) async {
      await _lists(t, _repo());
      expect(find.byKey(const Key('listMenu-2')), findsOneWidget);
      expect(find.byKey(const Key('listMenu-$kFavourites')), findsNothing);
    });

    testWidgets('nothing saved: an empty state', (t) async {
      await _lists(t, _repo());
      expect(find.byKey(const Key('savedEmpty')), findsOneWidget);
    });

    testWidgets('something saved: no empty state', (t) async {
      await _lists(
        t,
        _repo(
          items: {
            2: {5},
          },
        ),
      );
      expect(find.byKey(const Key('savedEmpty')), findsNothing);
    });

    testWidgets('a failed load can be retried', (t) async {
      final repo = _FlakyLists();
      await _lists(t, repo);
      expect(find.text('Something went wrong'), findsOneWidget);
      repo.fail = false;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Favourites'), findsOneWidget);
    });

    testWidgets('creates a list', (t) async {
      final repo = _repo();
      await _lists(t, repo);
      await t.tap(find.byKey(const Key('newList')));
      await t.pumpAndSettle();
      // no name, no button
      expect(
        t.widget<FilledButton>(find.byKey(const Key('listNameSave'))).onPressed,
        isNull,
      );
      await t.enterText(find.byKey(const Key('listName')), 'By the river');
      await t.pump();
      await t.tap(find.byKey(const Key('listNameSave')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('create:By the river'));
      expect(find.text('By the river'), findsOneWidget);
    });

    testWidgets('a taken name keeps the dialog open and says why', (t) async {
      final repo = _repo();
      await _lists(t, repo);
      await t.tap(find.byKey(const Key('newList')));
      await t.pumpAndSettle();
      repo.failWrites = ApiException(409, 'name_taken', 'x');
      await t.enterText(find.byKey(const Key('listName')), 'Rainy days');
      await t.pump();
      await t.tap(find.byKey(const Key('listNameSave')));
      await t.pumpAndSettle();
      expect(
        find.text('You already have a list with this name'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('listName')), findsOneWidget);
    });

    testWidgets('renames a list', (t) async {
      final repo = _repo();
      await _lists(t, repo);
      await t.tap(find.byKey(const Key('listMenu-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('renameList')));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Rainy days'), findsOneWidget);
      await t.enterText(find.byKey(const Key('listName')), 'Sunny days');
      await t.pump();
      await t.tap(find.byKey(const Key('listNameSave')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('rename:2:Sunny days'));
      expect(find.text('Sunny days'), findsOneWidget);
      expect(find.text('Rainy days'), findsNothing);
    });

    testWidgets('deleting asks first; cancelling keeps the list', (t) async {
      final repo = _repo();
      await _lists(t, repo);
      await t.tap(find.byKey(const Key('listMenu-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('deleteList')));
      await t.pumpAndSettle();
      expect(find.text('Delete list?'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('delete')), isEmpty);
      expect(find.text('Rainy days'), findsOneWidget);
    });

    testWidgets('deletes after confirming', (t) async {
      final repo = _repo();
      await _lists(t, repo);
      await t.tap(find.byKey(const Key('listMenu-2')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('deleteList')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmDeleteList')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('delete:2'));
      expect(find.text('Rainy days'), findsNothing);
    });

    testWidgets('a tap opens the list', (t) async {
      await _lists(
        t,
        _repo(
          items: {
            2: {5},
          },
        ),
      );
      await t.tap(find.text('Rainy days'));
      await t.pumpAndSettle();
      expect(find.text('Spot 5'), findsOneWidget);
      expect(find.byType(SavedListScreen), findsOneWidget);
    });

    for (final size in const [
      Size(320, 640),
      Size(844, 390),
      Size(1300, 800),
    ]) {
      testWidgets('content starts below the glass bar at $size', (t) async {
        portrait(t, size);
        await _lists(t, _repo());
        final context = t.element(find.byType(SavedListsScreen));
        final first = find.byKey(const Key('savedList-$kFavourites'));
        expect(
          t.getTopLeft(first).dy,
          greaterThanOrEqualTo(GlassAppBar.contentTop(context)),
        );
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('stays at a readable width on wide windows', (t) async {
      portrait(t, const Size(1300, 800));
      await _lists(t, _repo());
      expect(
        t.getSize(find.byKey(const Key('savedList-$kFavourites'))).width,
        lessThanOrEqualTo(680),
      );
    });
  });

  group('list page', () {
    testWidgets('shows its spots under its name', (t) async {
      portrait(t);
      await _list(
        t,
        _repo(
          items: {
            2: {5, 6},
          },
        ),
        2,
      );
      expect(find.text('Rainy days'), findsOneWidget);
      expect(find.text('Spot 5'), findsOneWidget);
      expect(find.text('Spot 6'), findsOneWidget);
      // spots without a photo show from above
      expect(find.byType(SatelliteThumb), findsNWidgets(2));
    });

    testWidgets('the first spot starts below the glass bar', (t) async {
      portrait(t);
      await _list(
        t,
        _repo(
          items: {
            2: {5},
          },
        ),
        2,
      );
      final context = t.element(find.byType(SavedListScreen));
      expect(
        t.getTopLeft(find.byKey(const Key('savedSpot-5'))).dy,
        greaterThanOrEqualTo(GlassAppBar.contentTop(context)),
      );
    });

    testWidgets('a tap opens the spot page', (t) async {
      portrait(t);
      await _list(
        t,
        _repo(
          items: {
            2: {5},
          },
        ),
        2,
      );
      await t.tap(find.text('Spot 5'));
      await t.pumpAndSettle();
      expect(find.text('spot page 5'), findsOneWidget);
    });

    testWidgets('removes a spot, and the lists page shows it', (t) async {
      portrait(t);
      final repo = _repo(
        items: {
          2: {5, 6},
        },
      );
      final router = await _list(t, repo, 2);
      await t.tap(find.byKey(const Key('removeSpot-5')));
      await t.pumpAndSettle();
      expect(repo.calls, contains('remove:2:5'));
      expect(find.text('Spot 5'), findsNothing);
      expect(find.text('Spot 6'), findsOneWidget);
      router.pop();
      await t.pumpAndSettle();
      expect(find.text('1 spot'), findsOneWidget);
    });

    testWidgets('a failed removal brings the spot back', (t) async {
      portrait(t);
      final repo = _repo(
        items: {
          2: {5},
        },
      );
      await _list(t, repo, 2);
      repo.failWrites = Exception('down');
      await t.tap(find.byKey(const Key('removeSpot-5')));
      await t.pumpAndSettle();
      expect(find.text('Spot 5'), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('an empty list says so, also after removing the last', (
      t,
    ) async {
      portrait(t);
      await _list(
        t,
        _repo(
          items: {
            2: {5},
          },
        ),
        2,
      );
      expect(find.byKey(const Key('savedListEmpty')), findsNothing);
      await t.tap(find.byKey(const Key('removeSpot-5')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('savedListEmpty')), findsOneWidget);
      expect(find.text('This list is still empty'), findsOneWidget);
    });

    testWidgets('loads the next page when scrolled', (t) async {
      portrait(t, const Size(400, 500));
      final repo = _repo(
        items: {
          2: {for (var i = 1; i <= 30; i++) i},
        },
      )..pageSize = 10;
      await _list(t, repo, 2);
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, -2000));
      await t.pumpAndSettle();
      expect(repo.calls, contains('spots:2:10'));
    });

    testWidgets('a list that is gone says so, without a retry', (t) async {
      portrait(t);
      final repo = _repo()
        ..failSpots = ApiException(404, 'not_found', 'list not found');
      await _list(t, repo, 2);
      expect(find.text('This list no longer exists'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('other errors can be retried', (t) async {
      portrait(t);
      final repo = _repo(
        items: {
          2: {5},
        },
      )..failSpots = Exception('down');
      await _list(t, repo, 2);
      expect(find.text('Something went wrong'), findsOneWidget);
      repo.failSpots = null;
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text('Spot 5'), findsOneWidget);
    });

    testWidgets('renames from the bar, and the title follows', (t) async {
      portrait(t);
      await _list(t, _repo(), 2);
      await t.tap(find.byKey(const Key('listMenu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('renameList')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('listName')), 'Sunny days');
      await t.pump();
      await t.tap(find.byKey(const Key('listNameSave')));
      await t.pumpAndSettle();
      expect(find.text('Sunny days'), findsOneWidget);
    });

    testWidgets('deleting from the bar goes back to the lists', (t) async {
      portrait(t);
      final repo = _repo();
      await _list(t, repo, 2);
      await t.tap(find.byKey(const Key('listMenu')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('deleteList')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmDeleteList')));
      await t.pumpAndSettle();
      expect(find.byType(SavedListScreen), findsNothing);
      expect(find.byType(SavedListsScreen), findsOneWidget);
      expect(find.text('Rainy days'), findsNothing);
    });

    testWidgets('Favourites have no rename or delete', (t) async {
      portrait(t);
      await _list(t, _repo(), kFavourites);
      expect(find.text('Favourites'), findsOneWidget);
      expect(find.byKey(const Key('listMenu')), findsNothing);
    });
  });
}

class _FlakyLists extends FakeSaved {
  bool fail = true;

  @override
  Future<List<SpotList>> lists() {
    if (fail) throw Exception('down');
    return super.lists();
  }
}
