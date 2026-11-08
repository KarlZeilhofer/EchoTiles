import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

SongAnalysis chart(List<AnalyzedNote> notes) => SongAnalysis.fromJson({
  'version': 2,
  'duration': 12,
  'bpm': 120,
  'notes': notes.map((n) => n.toJson()).toList(),
});

void main() {
  test('hold lengths survive lane balancing and save/load', () {
    final analysis = chart(const [
      AnalyzedNote(0.5, 0, duration: 0.6),
      AnalyzedNote(1.6, 0, duration: 1.3),
      AnalyzedNote(3.3, 1),
    ]);
    expect(analysis.notes.map((n) => n.duration), [0.6, 1.3, 0]);
    expect(
      SongAnalysis.fromJson(analysis.toJson()).toJson(),
      analysis.toJson(),
    );
  });

  test('old onset-only analyses still load as taps and retain version', () {
    final analysis = SongAnalysis.fromJson({
      'version': 1,
      'duration': 5,
      'bpm': 120,
      'notes': [
        {'time': 1, 'lane': 0},
      ],
    });
    expect(analysis.analysisVersion, 1);
    expect(analysis.notes.single.isLong, isFalse);
    expect(analysis.notes.single.duration, 0);
  });

  test('overlapping holds occupy separate lanes and remain playable', () {
    final analysis = chart([
      for (var i = 0; i < 8; i++) AnalyzedNote(i * 0.3, 0, duration: 2),
    ]);
    expect(analysis.notes.map((n) => n.time), [
      for (var i = 0; i < 8; i++) i * 0.3,
    ]);
    for (var i = 0; i < analysis.notes.length; i++) {
      final a = analysis.notes[i];
      for (final b
          in analysis.notes.skip(i + 1).where((n) => n.lane == a.lane)) {
        if (a.isLong) expect(a.endTime, lessThanOrEqualTo(b.time + 1e-6));
      }
    }
    expect(analysis.notes.map((n) => n.lane).toSet(), {0, 1, 2, 3});
    expect(
      SongAnalysis.fromJson(analysis.toJson()).toJson(),
      analysis.toJson(),
    );
  });

  test(
    'slider length scales with musical duration and tail arrives on time',
    () {
      for (final time in [0.0, 5.0, 10.0]) {
        final head = RhythmTimeline.position(time, time, 12);
        final tail = RhythmTimeline.position(time + 1, time, 12);
        final longerTail = RhythmTimeline.position(time + 2, time, 12);
        expect(head - longerTail, closeTo(2 * (head - tail), 1e-9));
        expect(RhythmTimeline.position(time + 1, time + 1, 12), 0.55);
      }
    },
  );

  test('slider minimum is one second, also for saved v2 analyses', () {
    final analysis = chart(const [
      AnalyzedNote(0, 0, duration: 0.4),
      AnalyzedNote(1, 1, duration: 0.8),
      AnalyzedNote(2, 2, duration: 0.999),
      AnalyzedNote(4, 3, duration: 1.0),
      AnalyzedNote(7, 0, duration: 1.5),
    ]);
    expect(analysis.notes.map((n) => n.isLong), [
      false,
      false,
      false,
      true,
      true,
    ]);
    expect(
      SongAnalysis.fromJson(analysis.toJson()).notes.map((n) => n.isLong),
      [false, false, false, true, true],
    );
  });

  test('invalid or out-of-track durations are rejected', () {
    for (final length in [-1.0, double.nan, double.infinity, 20.0]) {
      expect(
        () => chart([AnalyzedNote(1, 0, duration: length)]),
        throwsFormatException,
      );
    }
  });
}
