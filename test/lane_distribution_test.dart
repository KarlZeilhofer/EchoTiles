import 'package:echotiles/models/song_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

SongAnalysis decode(List<int> lanes) => SongAnalysis.fromJson({
  'version': SongAnalysis.version,
  'duration': 100,
  'bpm': 120,
  'notes': [
    for (var i = 0; i < lanes.length; i++) {'time': i * 0.35, 'lane': lanes[i]},
  ],
});

void expectBalanced(SongAnalysis analysis) {
  final lanes = analysis.notes.map((n) => n.lane).toList();
  for (var start = 0; start + 4 <= lanes.length; start += 4) {
    expect(lanes.sublist(start, start + 4).toSet(), {0, 1, 2, 3});
  }
  for (var i = 1; i < lanes.length; i++) {
    expect(lanes[i], isNot(lanes[i - 1]), reason: 'Adjacent notes $i');
  }
  final counts = [
    for (var lane = 0; lane < 4; lane++) lanes.where((l) => l == lane).length,
  ]..sort();
  expect(counts.last - counts.first, lessThanOrEqualTo(1));
}

void main() {
  test(
    'old single-lane charts immediately use all four lanes after loading',
    () {
      for (var preferred = 0; preferred < 4; preferred++) {
        final analysis = decode(List.filled(41, preferred));
        expectBalanced(analysis);
        expect(analysis.notes.first.lane, preferred);
        expect(analysis.notes.map((n) => n.time), [
          for (var i = 0; i < 41; i++) i * 0.35,
        ]);
        expect(analysis.duration, 100);
        expect(analysis.bpm, 120);
      }
    },
  );

  test('skewed and changing timbres stay balanced across group boundaries', () {
    final analysis = decode([
      ...List.filled(20, 0),
      ...List.filled(12, 3),
      0,
      1,
      2,
      3,
      3,
      2,
      1,
      0,
      2,
      2,
      0,
      0,
      1,
    ]);
    expectBalanced(analysis);
  });

  test('already balanced musical choices survive repeated save/load', () {
    final original = decode([0, 3, 1, 2, 1, 2, 0, 3]);
    expect(original.notes.map((n) => n.lane), [0, 3, 1, 2, 1, 2, 0, 3]);
    final restored = SongAnalysis.fromJson(original.toJson());
    expect(restored.toJson(), original.toJson());
    expectBalanced(restored);
  });

  test('short songs use as many different lanes as they have notes', () {
    for (var length = 1; length <= 4; length++) {
      final analysis = decode(List.filled(length, 0));
      expect(analysis.notes.map((n) => n.lane).toSet().length, length);
      expectBalanced(analysis);
    }
  });
}
