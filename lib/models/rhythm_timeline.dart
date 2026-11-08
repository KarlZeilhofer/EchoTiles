import 'dart:math';

/// Position is derived from audio time, so faster scrolling never moves a note
/// away from its detected musical onset at the judgment line.
class RhythmTimeline {
  static double speed(double time, double duration) =>
      0.5 * (1 + 1.5 * pow((time / duration).clamp(0.0, 1.0), 2.5));

  static double position(double noteTime, double time, double duration) =>
      0.8 - (noteTime - time) * speed(time, duration);
}
