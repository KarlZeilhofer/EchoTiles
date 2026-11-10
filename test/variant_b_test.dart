import 'package:echotiles/models/onset_candidate.dart';
import 'package:echotiles/models/rhythm_chart_planner.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:echotiles/models/tile_variant.dart';
import 'package:flutter_test/flutter_test.dart';

List<OnsetCandidate> pulseGrid(double duration, {bool doubles = false}) => [
  for (var i = 0; i * 0.25 < duration; i++)
    OnsetCandidate(
      AnalyzedNote(i * 0.25, i % 4),
      strength: i % 8 == 0 ? 3 : 1,
      doubleAccent: doubles && i % 8 == 0,
    ),
];

void expectHands(List<AnalyzedNote> notes) {
  for (final note in notes) {
    final active = notes
        .where(
          (n) =>
              n.time <= note.time + 1e-6 &&
              (n.isLong ? n.endTime : n.time) + 0.1 > note.time + 1e-6,
        )
        .toList();
    expect(active.length, lessThanOrEqualTo(2));
    expect(active.map((n) => n.lane ~/ 2).toSet().length, active.length);
  }
}

void main() {
  const quotas = [15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 38];
  void expectQuotas(List<AnalyzedNote> notes, double duration) {
    for (var start = 0.0; start < duration; start += 10) {
      expect(
        notes.where((n) => n.time >= start && n.time < start + 10).length,
        RhythmChartPlanner.windowQuota(start, duration),
        reason: 'Window $start',
      );
    }
    expectHands(notes);
  }

  test(
    'B meets identical exact ten-second quotas at different song tempos',
    () {
      for (final bpm in [0.0, 60.0, 80.0, 120.0, 180.0]) {
        final notes = RhythmChartPlanner.plan(pulseGrid(120), bpm, 120);
        expect(notes.length, 313);
        for (var i = 0; i < quotas.length; i++) {
          expect(
            notes
                .where((n) => n.time >= i * 10 && n.time < (i + 1) * 10)
                .length,
            quotas[i],
            reason: 'BPM $bpm, window $i',
          );
        }
        expect(notes.map((n) => n.lane).toSet(), {0, 1, 2, 3});
        expectQuotas(notes, 120);
      }
    },
  );

  test('B starts every full first window at 15 regardless of song length', () {
    for (final duration in [20.0, 60.0, 120.0, 600.0]) {
      expect(RhythmChartPlanner.windowQuota(0, duration), 15);
    }
  });

  test(
    'B fills sparse passages on the metrical grid instead of reducing rate',
    () {
      final input = pulseGrid(10);
      final notes = RhythmChartPlanner.plan(input, 120, 120);
      expect(notes.where((n) => n.time >= 10), isNotEmpty);
      expect(
        notes
            .where((n) => n.time >= 10)
            .every((n) => (n.time * 16 - (n.time * 16).round()).abs() < 1e-6),
        isTrue,
      );
      expectQuotas(notes, 120);
    },
  );

  test('strict slots spread notes across the entire window even for clustered input', () {
    final input = [
      for (var i = 0; i < 30; i++) OnsetCandidate(AnalyzedNote(i * 0.01, 0)),
    ];
    final notes = RhythmChartPlanner.plan(input, 120, 120);
    final intro = notes.where((n) => n.time < 10).toList();
    expect(intro.last.time, greaterThan(9));
    for (var i = 1; i < intro.length; i++) {
      expect(intro[i].time - intro[i - 1].time, lessThan(1.25));
    }
    expectQuotas(notes, 120);
  });

  test('B keeps audible chords on opposite hands within the exact quota', () {
    final input = pulseGrid(120, doubles: true);
    final notes = RhythmChartPlanner.plan(input, 120, 120);
    final chords = [
      for (var i = 1; i < notes.length; i++)
        if (notes[i].time == notes[i - 1].time) [notes[i - 1], notes[i]],
    ];
    expect(chords, isNotEmpty);
    for (final pair in chords) {
      expect(pair[0].lane ~/ 2, isNot(pair[1].lane ~/ 2));
      expect(
        input.any((c) => c.doubleAccent && c.note.time == pair[0].time),
        isTrue,
      );
    }
    expect(notes.where((n) => n.time == notes.first.time).length, 1);
    expectQuotas(notes, 120);
  });

  test(
    'overlapping vocals leave a thumb free and cannot underfill fixed quotas',
    () {
      final input = [
        for (var i = 0; i < 464; i++)
          OnsetCandidate(AnalyzedNote(i * 0.25, i % 4, duration: 4)),
      ];
      final notes = RhythmChartPlanner.plan(input, 120, 120);
      expect(notes.first.duration, 4);
      expect(notes.where((n) => n.isLong), isNotEmpty);
      for (final note in notes.where((n) => n.isLong)) {
        expect(
          notes
              .where(
                (n) => n.isLong && n.time <= note.time && n.endTime > note.time,
              )
              .length,
          1,
        );
      }
      expectQuotas(notes, 120);
    },
  );

  test(
    'partial final windows and short clips also have exact playable quotas',
    () {
      for (final duration in [0.12, 10.1, 10.2, 23.7, 120.01]) {
        final notes = RhythmChartPlanner.plan(
          const [OnsetCandidate(AnalyzedNote(0, 0, duration: 0))],
          75,
          duration,
        );
        expect(notes.every((n) => n.time >= 0 && n.time < duration), isTrue);
        expectQuotas(notes, duration);
      }
    },
  );

  test(
    'one v4 analysis can rebuild either variant without changing its evidence',
    () {
      final raw = {
        'version': 4,
        'duration': 120.0,
        'bpm': 120.0,
        'notes': [
          for (var i = 0; i < 240; i++) AnalyzedNote(i * 0.5, i % 4).toJson(),
        ],
        'candidates': pulseGrid(
          120,
          doubles: true,
        ).map((c) => c.toJson()).toList(),
      };
      final a = SongAnalysis.fromJson(raw, variant: TileVariant.a);
      final b = SongAnalysis.fromJson(raw, variant: TileVariant.b);
      expect(a.notes.length, 240);
      expect(b.notes.length, isNot(a.notes.length));
      expect(a.toJson(), b.toJson());
      expect(
        SongAnalysis.fromJson(
          b.toJson(),
          variant: TileVariant.b,
        ).notes.map((n) => n.toJson()),
        b.notes.map((n) => n.toJson()),
      );
    },
  );

  test('sliders are capped at four seconds for both old and new analyses', () {
    for (final version in [1, 2, 3, 4]) {
      final analysis = SongAnalysis.fromJson({
        'version': version,
        'duration': 20,
        'bpm': 120,
        'notes': [
          const AnalyzedNote(1, 0, duration: 10).toJson(),
          const AnalyzedNote(6, 0).toJson(),
        ],
      });
      expect(analysis.notes.first.duration, 4);
      expect(analysis.notes.length, 2);
    }
  });

  test(
    'B speed increases linearly and no head or tail drifts off its audio time',
    () {
      var previousSpeed = RhythmTimeline.speed(0, 120, variant: TileVariant.b);
      for (var t = 10.0; t <= 120; t += 10) {
        final speed = RhythmTimeline.speed(t, 120, variant: TileVariant.b);
        expect(speed - previousSpeed, closeTo(0.0625, 1e-9));
        expect(
          RhythmTimeline.position(t, t, 120, variant: TileVariant.b),
          0.55,
        );
        previousSpeed = speed;
      }
      double step(double note) =>
          RhythmTimeline.position(note, 50.016, 120, variant: TileVariant.b) -
          RhythmTimeline.position(note, 50, 120, variant: TileVariant.b);
      expect(step(49), closeTo(step(54), 1e-9));
      expect(step(51), closeTo(step(80), 1e-9));
    },
  );
}
