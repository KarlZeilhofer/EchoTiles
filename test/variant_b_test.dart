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
  test(
    'B ten-second tile budgets follow a linear ramp on audible subdivisions',
    () {
      final input = pulseGrid(120);
      final notes = RhythmChartPlanner.plan(input, 120, 120);
      expect(notes.map((n) => n.lane).toSet(), {0, 1, 2, 3});
      final counts = <int>[];
      for (var start = 0.0; start < 120; start += 10) {
        final count = notes
            .where((n) => n.time >= start && n.time < start + 10)
            .length;
        counts.add(count);
        final expected = 10 * RhythmChartPlanner.density(start + 5, 120, 1.5);
        expect(count, closeTo(expected, 1), reason: 'Window $start');
      }
      expect(counts.first, 16);
      expect(counts.last, 37);
      final intro = notes.where((n) => n.time < 10).toList();
      expect(
        intro.map((n) => n.time),
        containsAll([for (var i = 0; i < 10; i++) i.toDouble()]),
      );
      expect(
        intro.where((n) => n.time % 1 == 0.5).length,
        greaterThanOrEqualTo(5),
      );
      expect(
        notes.where((n) => n.time >= 110).any((n) => n.time % 1 == 0.5),
        isTrue,
      );
      expect(
        notes.every((n) => input.any((c) => c.note.time == n.time)),
        isTrue,
      );
      expectHands(notes);
    },
  );

  test('B supports strong two-band accents on opposite thumbs only', () {
    final notes = RhythmChartPlanner.plan(
      pulseGrid(120, doubles: true),
      120,
      120,
    );
    final simultaneous = [
      for (var i = 1; i < notes.length; i++)
        if (notes[i].time == notes[i - 1].time) [notes[i - 1], notes[i]],
    ];
    expect(simultaneous, isNotEmpty);
    for (final pair in simultaneous) {
      expect(pair[0].lane ~/ 2, isNot(pair[1].lane ~/ 2));
      expect(pair[0].time % 2, 0);
    }
    expect(notes.where((n) => n.time == notes.first.time).length, 1);
    expectHands(notes);
  });

  test('B has rhythmic extra taps on the free thumb while a vocal is held', () {
    final input = pulseGrid(20);
    input[0] = const OnsetCandidate(
      AnalyzedNote(0, 0, duration: 4),
      strength: 3,
    );
    final notes = RhythmChartPlanner.plan(input, 120, 20);
    expect(notes.first.isLong, isTrue);
    final extra = notes.skip(1).where((n) => n.time < 4.1).toList();
    expect(extra.length, greaterThanOrEqualTo(2));
    expect(extra.every((n) => n.lane ~/ 2 != notes.first.lane ~/ 2), isTrue);
    expectHands(notes);
  });

  test(
    'B never fills silence or invents duplicate mono notes to meet quotas',
    () {
      final input = [
        ...pulseGrid(10),
        ...pulseGrid(10).map(
          (c) => OnsetCandidate(
            AnalyzedNote(c.note.time + 30, c.note.lane),
            strength: c.strength,
          ),
        ),
      ];
      final notes = RhythmChartPlanner.plan(input, 120, 40);
      expect(notes.any((n) => n.time >= 10 && n.time < 30), isFalse);
      expect(notes.map((n) => n.time).toSet().length, notes.length);
      expectHands(notes);
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

  test('a quiet rest of the song cannot thin an active introduction', () {
    final input = pulseGrid(10);
    final notes = RhythmChartPlanner.plan(input, 120, 120);
    expect(notes.where((n) => n.time < 10).length, 16);
    expect(notes.every((n) => n.time < 10), isTrue);
    expectHands(notes);
  });

  test('unknown tempo also gets an active intro without fabricated notes', () {
    final input = pulseGrid(120);
    final notes = RhythmChartPlanner.plan(input, 0, 120);
    expect(notes.where((n) => n.time < 10).length, 16);
    expect(notes.every((n) => input.any((c) => c.note.time == n.time)), isTrue);
    expectHands(notes);
  });

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
