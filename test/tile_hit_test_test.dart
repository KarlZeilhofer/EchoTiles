import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/tile_hit_test.dart';
import 'package:flutter_test/flutter_test.dart';

GameTile tile({
  int id = 1,
  int lane = 0,
  double bottom = 0.6,
  double length = 1,
}) => GameTile(id: id, lane: lane, y: bottom, length: length);

void main() {
  // Golden cases taken from F-Droid 1.0.0 (6829d30), whose tolerances are
  // 0.08 for the rectangle and 0.18 for the target-line region.
  test(
    'visible tiles above and below the line are clickable without a time gate',
    () {
      final above = tile(bottom: 0.3);
      final below = tile(bottom: 0.9);
      expect(TileHitTest.select([above], 0, 0.2, 0.55), same(above));
      expect(TileHitTest.select([below], 0, 0.8, 0.55), same(below));
      expect(TileHitTest.isMissed(below), isFalse);
    },
  );

  test('the original rectangle padding is honored at both edges', () {
    final t = tile(bottom: 0.3);
    expect(TileHitTest.select([t], 0, 0.02, 0.8), same(t));
    expect(TileHitTest.select([t], 0, 0.38, 0.8), same(t));
    expect(TileHitTest.select([t], 0, 0.019, 0.8), isNull);
    expect(TileHitTest.select([t], 0, 0.381, 0.8), isNull);
  });

  test('target-line fallback retains the original broad tolerance', () {
    final t = tile(bottom: 0.621);
    expect(TileHitTest.select([t], 0, 0.8, 0.8), same(t));
    expect(TileHitTest.select([tile(bottom: 0.619)], 0, 0.8, 0.8), isNull);
  });

  test(
    'the lowest visible candidate wins and already cleared tiles are ignored',
    () {
      final lower = tile(id: 1, bottom: 0.6);
      final upper = tile(id: 2, bottom: 0.5);
      expect(TileHitTest.select([upper, lower], 0, 0.5, 0.55), same(lower));
      lower.isHolding = true;
      expect(TileHitTest.select([upper, lower], 0, 0.5, 0.55), same(upper));
      expect(TileHitTest.select([upper], 1, 0.5, 0.55), isNull);
    },
  );

  test(
    'misses use the original screen edge, not elapsed time after the beat',
    () {
      expect(TileHitTest.isMissed(tile(bottom: 1.02)), isFalse);
      final t = tile(bottom: 1.02001);
      expect(TileHitTest.isMissed(t), isTrue);
      t.isHolding = true;
      expect(TileHitTest.isMissed(t), isFalse);
      t.isHolding = false;
      t.isHit = true;
      expect(TileHitTest.isMissed(t), isFalse);
    },
  );

  test('a skipped older tile below the screen still blocks a newer hit', () {
    final old = tile(id: 0, bottom: 1.25);
    final current = tile(id: 1);
    expect(TileHitTest.select([old, current], 0, 0.5, 0.55), isNull);
    old.isHit = true;
    expect(TileHitTest.select([old, current], 0, 0.5, 0.55), same(current));
  });

  test(
    'rating is based on the visible rectangle distance as in the original',
    () {
      expect(TileHitTest.quality(tile(bottom: 0.9), 0.8), HitQuality.perfect);
      expect(TileHitTest.quality(tile(bottom: 0.77), 0.8), HitQuality.perfect);
      expect(TileHitTest.quality(tile(bottom: 0.72), 0.8), HitQuality.great);
      expect(TileHitTest.quality(tile(bottom: 0.65), 0.8), HitQuality.good);
    },
  );

  test('long-note painting and input share bottom-anchored bounds', () {
    final t = tile(bottom: 0.7, length: 3);
    expect(TileHitTest.height(t), closeTo(0.6, 1e-9));
    expect(TileHitTest.top(t), closeTo(0.1, 1e-9));
    expect(TileHitTest.select([t], 0, 0.15, 0.55), same(t));
  });
}
