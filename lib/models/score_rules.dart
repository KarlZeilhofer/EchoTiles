import 'game_models.dart';

/// Rate the complete reward, so combo and sustain bonuses cannot dilute the
/// difference between perfect, great and good hits.
class ScoreRules {
  static double multiplier(HitQuality quality) => switch (quality) {
    HitQuality.perfect => 1,
    HitQuality.great => 0.8,
    HitQuality.good => 0.5,
    HitQuality.miss => 0,
  };

  static int tap(HitQuality quality, int combo) =>
      ((100 + combo * 2) * multiplier(quality)).floor();

  static double holdRate(HitQuality quality) => 220 * multiplier(quality);
  static int completion(HitQuality quality) =>
      (150 * multiplier(quality)).floor();
  static int earlyRelease(HitQuality quality) =>
      (100 * multiplier(quality)).floor();
}
