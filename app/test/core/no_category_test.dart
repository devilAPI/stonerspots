import 'package:app/core/models.dart';
import 'package:app/features/admin/admin_models.dart';
import 'package:app/features/map/spot_marker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('spotIcon (tags only)', () {
    test('priority roof > water > view > seating', () {
      expect(spotIcon([SpotTag.seating, SpotTag.roof]), Icons.roofing);
      expect(spotIcon([SpotTag.view, SpotTag.water]), Icons.water_drop);
      expect(spotIcon([SpotTag.seating, SpotTag.view]), Icons.landscape);
      expect(spotIcon([SpotTag.seating]), Icons.chair_alt);
    });
    test('no matching tag gives the generic icon', () {
      expect(spotIcon(const []), Icons.place);
      expect(spotIcon([SpotTag.quiet, SpotTag.lit]), Icons.place);
    });
  });

  test('a stray category key from an old server is ignored', () {
    final s = Spot.fromJson({
      'id': 1,
      'title': 'T',
      'category': 'bench',
      'lat': 48.1,
      'lon': 11.6,
    });
    expect(s.id, 1);
    final f = FeedItem.fromJson({
      'id': 1,
      'created_at': '2026-10-24T10:00:00Z',
      'author': {'id': 1, 'display_name': 'A'},
      'spot': {'id': 5, 'title': 'T', 'category': 'lake', 'lat': 1, 'lon': 2},
    });
    expect(f.updateCount, 1);
  });

  test('FeedItem parses update_count', () {
    final f = FeedItem.fromJson({
      'id': 1,
      'created_at': '2026-10-24T10:00:00Z',
      'author': {'id': 1, 'display_name': 'A'},
      'spot': {'id': 5, 'title': 'T', 'lat': 1, 'lon': 2},
      'update_count': 3,
    });
    expect(f.updateCount, 3);
  });

  test('AdminSpotPatch has no category', () {
    expect(
      const AdminSpotPatch(title: 'x').toJson().containsKey('category'),
      isFalse,
    );
  });
}
