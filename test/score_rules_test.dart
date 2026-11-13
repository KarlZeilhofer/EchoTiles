import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/score_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tap quality scales the entire reward including a growing combo', () {
    for (final combo in [1, 10, 100, 1000]) {
      final perfect = ScoreRules.tap(HitQuality.perfect, combo);
      final great = ScoreRules.tap(HitQuality.great, combo);
      final good = ScoreRules.tap(HitQuality.good, combo);
      expect(perfect, 100 + combo * 2);
      expect(great, (perfect * 0.8).floor());
      expect(good, (perfect * 0.5).floor());
      expect(perfect, greaterThan(great));
      expect(great, greaterThan(good));
    }
  });

  test(
    'hold rate, full bonus and early release all retain the attack grade',
    () {
      expect(ScoreRules.holdRate(HitQuality.perfect), 220);
      expect(ScoreRules.holdRate(HitQuality.great), 176);
      expect(ScoreRules.holdRate(HitQuality.good), 110);
      expect(ScoreRules.completion(HitQuality.perfect), 150);
      expect(ScoreRules.completion(HitQuality.great), 120);
      expect(ScoreRules.completion(HitQuality.good), 75);
      expect(ScoreRules.earlyRelease(HitQuality.perfect), 100);
      expect(ScoreRules.earlyRelease(HitQuality.great), 80);
      expect(ScoreRules.earlyRelease(HitQuality.good), 50);
      for (final seconds in [1.0, 2.5, 4.0]) {
        double total(HitQuality q) =>
            ScoreRules.tap(q, 30) +
            seconds * ScoreRules.holdRate(q) +
            ScoreRules.completion(q);
        expect(total(HitQuality.perfect), greaterThan(total(HitQuality.great)));
        expect(total(HitQuality.great), greaterThan(total(HitQuality.good)));
      }
    },
  );

  test('misses cannot receive any kind of reward', () {
    expect(ScoreRules.tap(HitQuality.miss, 100), 0);
    expect(ScoreRules.holdRate(HitQuality.miss), 0);
    expect(ScoreRules.completion(HitQuality.miss), 0);
    expect(ScoreRules.earlyRelease(HitQuality.miss), 0);
  });
}
