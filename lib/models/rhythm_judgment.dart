import 'game_models.dart';

class RhythmJudgment {
  static const perfectWindow = 0.05;
  static const greatWindow = 0.10;
  static const hitWindow = 0.22;
  static const inputGrace = 0.12;

  static HitQuality quality(double noteTime, double inputTime) {
    final distance = (noteTime - inputTime).abs();
    if (distance <= perfectWindow + 1e-9) return HitQuality.perfect;
    if (distance <= greatWindow + 1e-9) return HitQuality.great;
    if (distance <= hitWindow + 1e-9) return HitQuality.good;
    return HitQuality.miss;
  }

  // Give queued hardware events time to arrive before ending the run.
  static bool isOverdue(double noteTime, double songTime) =>
      songTime - noteTime > hitWindow + inputGrace;

  static double inputTime({
    required double songTime,
    required Duration eventTime,
    required Duration frameTime,
    required double elapsedSinceFrame,
  }) {
    // Synthetic test/accessibility events may not carry a hardware timestamp.
    if (eventTime == Duration.zero) return songTime;
    final age =
        (frameTime - eventTime).inMicroseconds / 1000000 + elapsedSinceFrame;
    if (age < 0 || age > 1) return songTime;
    return songTime - age.clamp(0.0, inputGrace);
  }
}
