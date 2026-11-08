import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/rhythm_judgment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('judgments are symmetric and boundary taps remain valid', () {
    for (final sign in [-1, 1]) {
      expect(RhythmJudgment.quality(10, 10 + sign * 0.05), HitQuality.perfect);
      expect(RhythmJudgment.quality(10, 10 + sign * 0.10), HitQuality.great);
      expect(RhythmJudgment.quality(10, 10 + sign * 0.22), HitQuality.good);
      expect(RhythmJudgment.quality(10, 10 + sign * 0.221), HitQuality.miss);
    }
  });

  test('delayed event handling scores the actual touch time', () {
    final inputTime = RhythmJudgment.inputTime(
      songTime: 10.07,
      eventTime: const Duration(milliseconds: 20100),
      frameTime: const Duration(seconds: 20),
      elapsedSinceFrame: 0.17,
    );
    expect(inputTime, closeTo(10, 1e-9));
    expect(RhythmJudgment.quality(10, inputTime), HitQuality.perfect);
  });

  test('queued valid taps have time to arrive before a miss is declared', () {
    expect(RhythmJudgment.isOverdue(10, 10.28), isFalse);
    final inputTime = RhythmJudgment.inputTime(
      songTime: 10.28,
      eventTime: const Duration(milliseconds: 20200),
      frameTime: const Duration(seconds: 20),
      elapsedSinceFrame: 0.28,
    );
    expect(RhythmJudgment.quality(10, inputTime), HitQuality.good);
    expect(RhythmJudgment.isOverdue(10, 10.35), isTrue);
  });

  test('missing or unrelated event timestamps do not shift a valid tap', () {
    for (final stamp in [
      Duration.zero,
      const Duration(seconds: 1),
      const Duration(seconds: 30),
    ]) {
      expect(
        RhythmJudgment.inputTime(
          songTime: 10,
          eventTime: stamp,
          frameTime: const Duration(seconds: 20),
          elapsedSinceFrame: 0.01,
        ),
        10,
      );
    }
  });
}
