import 'dart:math';

import 'tile_variant.dart';

/// Position is derived from audio time, so faster scrolling never moves a note
/// away from its detected musical onset at the judgment line.
class RhythmTimeline {
  // 45% above the bottom edge of the playfield.
  static const targetLineFactor = 0.55;

  static double speed(
    double time,
    double duration, {
    TileVariant variant = TileVariant.a,
  }) {
    final progress = (time / duration).clamp(0.0, 1.0);
    return 0.5 *
        (1 + 1.5 * (variant == TileVariant.b ? progress : pow(progress, 2.5)));
  }

  static double position(
    double noteTime,
    double time,
    double duration, {
    TileVariant variant = TileVariant.a,
  }) {
    if (variant == TileVariant.a) {
      return targetLineFactor - (noteTime - time) * speed(time, duration);
    }
    // Integrate linear speed. All heads/tails move by the same distance each
    // frame; their original audio timestamps still cross the line exactly.
    double distance(double t) {
      if (t < 0) return t * 0.5;
      if (t > duration) return duration * 0.875 + (t - duration) * 1.25;
      return t * 0.5 + 0.375 * t * t / duration;
    }

    return targetLineFactor - (distance(noteTime) - distance(time));
  }
}
