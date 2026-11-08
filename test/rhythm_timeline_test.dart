import 'package:flutter_test/flutter_test.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/song_analysis.dart';

void main() {
  test('scroll speed increases to 2.5x without shifting musical hit times', () {
    const duration = 120.0;
    expect(RhythmTimeline.speed(0, duration), 0.5);
    expect(RhythmTimeline.speed(duration, duration), 1.25);
    var previous = 0.0;
    for (var time = 0.0; time <= duration; time += 5) {
      final speed = RhythmTimeline.speed(time, duration);
      expect(speed, greaterThan(previous));
      expect(RhythmTimeline.position(time, time, duration), 0.8);
      expect(
        RhythmTimeline.position(time + 0.2, time, duration),
        lessThan(0.8),
      );
      expect(
        RhythmTimeline.position(time - 0.2, time, duration),
        greaterThan(0.8),
      );
      previous = speed;
    }
  });

  test('chart roundtrip preserves onsets and lanes', () {
    const analysis = SongAnalysis(
      duration: 3,
      bpm: 120,
      notes: [AnalyzedNote(0, 0), AnalyzedNote(0.5, 3), AnalyzedNote(2, 1)],
    );
    final restored = SongAnalysis.fromJson(analysis.toJson());
    expect(restored.notes.map((n) => n.time), [0, 0.5, 2]);
    expect(restored.notes.map((n) => n.lane), [0, 3, 1]);
  });

  test('invalid or stale cache cannot drive gameplay', () {
    final invalid = [
      {'time': -0.1, 'lane': 0},
      {'time': 0.1, 'lane': 4},
      {'time': 4.0, 'lane': 0},
      {'time': double.nan, 'lane': 0},
    ];
    for (final note in invalid) {
      expect(
        () => SongAnalysis.fromJson({
          'version': 1,
          'duration': 3,
          'bpm': 120,
          'notes': [note],
        }),
        throwsFormatException,
      );
    }
    expect(() => SongAnalysis.fromJson({'version': 0}), throwsFormatException);
    expect(
      () => SongAnalysis.fromJson({
        'version': 1,
        'duration': 3,
        'bpm': 120,
        'notes': [
          {'time': 1, 'lane': 0},
          {'time': 0, 'lane': 1},
        ],
      }),
      throwsFormatException,
    );
  });
}
