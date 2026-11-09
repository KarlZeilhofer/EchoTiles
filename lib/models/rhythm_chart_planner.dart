import 'dart:math';

import 'analyzed_note.dart';
import 'onset_candidate.dart';

/// Variant B selects measured onsets; the grid only ranks them, never moves
/// them or fabricates notes in silence. Four beats/bar is a ranking assumption,
/// not a claim to transcribe the recording's time signature.
class RhythmChartPlanner {
  static const windowSeconds = 10.0;
  static const startSpeed = 0.5;
  static const endFactor = 2.5;

  static double density(double time, double duration, double baseRate) =>
      baseRate * (1 + (endFactor - 1) * (time / duration).clamp(0.0, 1.0));

  static List<AnalyzedNote> plan(
    List<OnsetCandidate> input,
    double bpm,
    double duration,
  ) {
    if (input.isEmpty) return [];
    // Start with roughly three attacks per four beats, rather than one per
    // bar. Quiet sections elsewhere must not thin an otherwise active intro;
    // each window already limits selection to its actual playable onsets.
    final baseRate = bpm > 0 ? bpm / 80 : 1.5;
    final result = <AnalyzedNote>[];
    final busyUntil = [0.0, 0.0];
    final laneBag = <int>{};
    var carry = 0.0;
    var cursor = 0;
    _BeatGrid? grid;
    for (var start = 0.0; start < duration; start += windowSeconds) {
      final end = min(duration, start + windowSeconds);
      final section = <OnsetCandidate>[];
      while (cursor < input.length &&
          input[cursor].note.time < end + (end == duration ? 1e-6 : 0)) {
        section.add(input[cursor++]);
      }
      final expected =
          (end - start) *
          (density(start, duration, baseRate) +
              density(end, duration, baseRate)) /
          2;
      final quota = (expected + carry).round();
      carry +=
          expected -
          quota; // Do not carry a quiet passage's missing notes forward.
      if (section.isEmpty) continue;
      grid = _BeatGrid.fit(section, bpm, grid);
      final chosen = <OnsetCandidate>[];
      // Only the last four seconds can still occupy a hand in this window.
      final occupied = result.where((n) => _end(n) > start).toList();
      final options = <_Option>[];
      final strengths = section.map((c) => c.strength).toList()..sort();
      final median = max(1e-9, strengths[strengths.length ~/ 2]);
      for (final candidate in section) {
        final rank = grid.rank(candidate.note.time);
        final priority = identical(candidate, input.first)
            ? -1.0
            : candidate.note.isLong
            ? min(rank.toDouble(), 1.5)
            : rank.toDouble();
        options.add(_Option(candidate, priority));
        if (!identical(candidate, input.first) &&
            candidate.doubleAccent &&
            !candidate.note.isLong &&
            rank <= 1 &&
            candidate.strength >= median * 1.25) {
          options.add(_Option(candidate, 1.75, extra: true));
        }
      }
      final target = max(1, quota);
      final picked = <_Option>[];
      while (options.isNotEmpty && picked.length < target) {
        final priority = options.map((o) => o.priority).reduce(min);
        final tier = options.where((o) => o.priority == priority).toList();
        double value(_Option option) {
          final peers = picked.where((p) => p.priority == priority);
          final spacing = peers.isEmpty
              ? 1.0
              : min(
                  1.0,
                  peers
                      .map(
                        (p) =>
                            (p.candidate.note.time - option.candidate.note.time)
                                .abs() /
                            2,
                      )
                      .reduce(min),
                );
          final salience =
              sqrt(option.candidate.strength / median).clamp(0.0, 3.0) / 3;
          return salience + spacing * 0.7;
        }

        final option = tier.reduce((a, b) => value(a) >= value(b) ? a : b);
        options.remove(option);
        if (option.extra && !chosen.contains(option.candidate)) continue;
        final note = option.candidate.note;
        if (!_fits(note, occupied)) continue;
        chosen.add(option.candidate);
        occupied.add(note);
        picked.add(option);
      }
      chosen.sort((a, b) => a.note.time.compareTo(b.note.time));
      for (final candidate in chosen) {
        final note = candidate.note;
        final hands = [
          for (var h = 0; h < 2; h++)
            if (busyUntil[h] <= note.time + 1e-6) h,
        ];
        if (hands.isEmpty) continue;
        if (laneBag.isEmpty) laneBag.addAll([0, 1, 2, 3]);
        final free = [
          for (final h in hands) h * 2,
          for (final h in hands) h * 2 + 1,
        ];
        var lanes = free.where(laneBag.contains).toList();
        if (lanes.isEmpty) lanes = free;
        final lane = lanes.reduce(
          (a, b) => (a - note.lane).abs() <= (b - note.lane).abs() ? a : b,
        );
        result.add(AnalyzedNote(note.time, lane, duration: note.duration));
        busyUntil[lane ~/ 2] = _end(note);
        laneBag.remove(lane);
      }
    }
    return result;
  }

  static double _end(AnalyzedNote note) =>
      (note.isLong ? note.endTime : note.time) +
      AnalyzedNote.holdReleaseTolerance;

  static bool _fits(AnalyzedNote note, List<AnalyzedNote> selected) {
    final end = _end(note);
    final overlap = selected
        .where((n) => n.time < end - 1e-6 && _end(n) > note.time + 1e-6)
        .toList();
    for (final time in [
      note.time,
      ...overlap.map((n) => n.time).where((t) => t >= note.time),
    ]) {
      if (overlap
              .where((n) => n.time <= time + 1e-6 && _end(n) > time + 1e-6)
              .length >=
          2) {
        return false;
      }
    }
    return true;
  }
}

class _Option {
  final OnsetCandidate candidate;
  final double priority;
  final bool extra;
  _Option(this.candidate, this.priority, {this.extra = false});
}

class _BeatGrid {
  final double period;
  final double origin;
  final int beatOffset;
  _BeatGrid(this.period, this.origin, this.beatOffset);

  static _BeatGrid fit(
    List<OnsetCandidate> section,
    double bpm,
    _BeatGrid? previous,
  ) {
    final base = bpm > 0 ? 60 / bpm : 0.5;
    final anchors = [...section]
      ..sort((a, b) => b.strength.compareTo(a.strength));
    var bestPeriod = base;
    var bestOrigin = anchors.first.note.time;
    var bestScore = -1.0;
    // Local phase/tempo fitting avoids accumulating an integer-BPM estimate's
    // error across a whole song, and can follow moderate tempo changes.
    for (var step = -40; step <= 40; step++) {
      final period = base * (1 + step * 0.002);
      for (final anchor in anchors.take(12)) {
        var score = 0.0;
        for (final onset in section) {
          final beat = (onset.note.time - anchor.note.time) / period;
          final error = (beat - beat.round()).abs() * period;
          score +=
              sqrt(onset.strength) *
              exp(-0.5 * pow(error / min(0.04, period * 0.10), 2));
        }
        score *= 1 - (period / base - 1).abs() * 0.05;
        if (score > bestScore) {
          bestScore = score;
          bestPeriod = period;
          bestOrigin = anchor.note.time;
        }
      }
    }
    final offset = previous == null
        ? ((bestOrigin - section.first.note.time) / bestPeriod).round()
        : previous.beatOffset +
              ((bestOrigin - previous.origin) / previous.period).round();
    return _BeatGrid(bestPeriod, bestOrigin, offset);
  }

  int rank(double time) {
    final beat = (time - origin) / period + beatOffset;
    for (final (rank, spacing) in [(0, 4.0), (1, 2.0), (2, 1.0), (3, 0.5)]) {
      if ((beat - (beat / spacing).round() * spacing).abs() * period <=
          min(0.055, period * 0.12)) {
        return rank;
      }
    }
    return 4; // A real off-grid accent remains eligible, at its original time.
  }
}
