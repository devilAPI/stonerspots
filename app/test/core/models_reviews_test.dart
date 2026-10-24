import 'package:app/core/models.dart';
import 'package:app/features/reviews/review_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> feedJson({Map<String, dynamic>? extra}) => {
  'id': 1,
  'body': 'b',
  'photos': [],
  'created_at': '2026-10-24T10:00:00Z',
  'author': {'id': 2, 'display_name': 'A'},
  'spot': {'id': 5, 'title': 'T', 'lat': 1.0, 'lon': 2.0},
  ...?extra,
};

void main() {
  test('Spot parses rating fields and defaults to zero', () {
    final s = Spot.fromJson({
      'id': 1,
      'title': 't',
      'lat': 1,
      'lon': 2,
      'rating_avg': 4.5,
      'rating_count': 3,
    });
    expect(s.ratingAvg, 4.5);
    expect(s.ratingCount, 3);
    final d = Spot.fromJson({'id': 1, 'title': 't', 'lat': 1, 'lon': 2});
    expect(d.ratingAvg, 0);
    expect(d.ratingCount, 0);
    final i = Spot.fromJson({
      'id': 1,
      'lat': 1,
      'lon': 2,
      'rating_avg': 4,
      'rating_count': 1,
    });
    expect(i.ratingAvg, 4.0);
  });

  test('FeedItem parses tag and edited_at with defaults', () {
    final a = FeedItem.fromJson(
      feedJson(
        extra: {'tag': 'still_good', 'edited_at': '2026-10-25T10:00:00Z'},
      ),
    );
    expect(a.tag, UpdateTag.stillGood);
    expect(a.editedAt, DateTime.parse('2026-10-25T10:00:00Z'));
    final b = FeedItem.fromJson(feedJson());
    expect(b.tag, UpdateTag.note);
    expect(b.editedAt, isNull);
    expect(
      FeedItem.fromJson(feedJson(extra: {'tag': 'wat'})).tag,
      UpdateTag.note,
    );
  });

  test('UpdateTag wire names round-trip', () {
    for (final t in UpdateTag.values) {
      expect(UpdateTag.fromWire(t.wire), t);
    }
    expect(UpdateTag.crowded.wire, 'crowded');
    expect(UpdateTag.stillGood.wire, 'still_good');
    expect(UpdateTag.fromWire(null), UpdateTag.note);
  });

  test('ReviewsPage parses summary, mine, items and cursor', () {
    final r = {
      'id': 1,
      'rating': 4,
      'body': 'nice',
      'created_at': '2026-10-24T10:00:00Z',
      'updated_at': '2026-10-25T10:00:00Z',
      'author': {'id': 9, 'display_name': 'Bo'},
    };
    final p = ReviewsPage.fromJson({
      'summary': {
        'avg': 4.3,
        'count': 12,
        'distribution': {'1': 0, '2': 1, '3': 2, '4': 4, '5': 5},
      },
      'mine': r,
      'items': [r],
      'next_cursor': 'abc',
    });
    expect(p.summary.avg, 4.3);
    expect(p.summary.count, 12);
    expect(p.summary.distribution[5], 5);
    expect(p.mine!.author.displayName, 'Bo');
    expect(p.items.single.isEdited, isTrue);
    expect(p.nextCursor, 'abc');
    final e = ReviewsPage.fromJson({
      'summary': {'avg': 0, 'count': 0, 'distribution': {}},
      'mine': null,
      'items': [],
      'next_cursor': null,
    });
    expect(e.mine, isNull);
    expect(e.nextCursor, isNull);
    expect(e.summary.distribution[3], 0);
  });
}
