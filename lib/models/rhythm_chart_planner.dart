import 'dart:math';

import 'analyzed_note.dart';
import 'onset_candidate.dart';

/// Variant B has song-independent ten-second quotas. Prefer measured attacks;
/// complete missing slots with metrical notes rather than underfill the quota.
class RhythmChartPlanner {
  static const windowSeconds = 10.0;
  static const initialRate = 1.5;
  static const endFactor = 2.5;

  static double density(double time, double duration) {
    final windows = (duration / windowSeconds).ceil();
    final progress = windows <= 1
        ? 0.0
        : (time / windowSeconds).floor().clamp(0, windows - 1) / (windows - 1);
    return initialRate * (1 + (endFactor - 1) * progress);
  }

  static int windowQuota(double start, double duration) {
    if (start >= duration) return 0;
    final quota =
        ((min(duration, start + windowSeconds) - start) *
                density(start, duration))
            .round();
    return start == 0 ? max(1, quota) : quota;
  }

  static List<AnalyzedNote> plan(
    List<OnsetCandidate> input,
    double bpm,
    double duration,
  ) {
    if (input.isEmpty) return [];
    final result = <AnalyzedNote>[];
    final busyUntil = [0.0, 0.0];
    final laneBag = <int>{};
    var holdBusyUntil = 0.0;
    var cursor = 0;
    _BeatGrid? previousGrid;
    for (var start = 0.0; start < duration; start += windowSeconds) {
      final end = min(duration, start + windowSeconds);
      final section = <OnsetCandidate>[];
      while (cursor < input.length && input[cursor].note.time < end) {
        section.add(input[cursor++]);
      }
      final grid = section.isNotEmpty
          ? _BeatGrid.fit(section, bpm, previousGrid)
          : previousGrid ??
                _BeatGrid(bpm > 0 ? 60 / bpm : 0.5, input.first.note.time, 0);
      previousGrid = grid;
      final quota = windowQuota(start, duration);
      if (quota == 0) continue;
      final width = (end - start) / quota;
      // A fine, beat-aligned fallback always fits the paced slots, including
      // at slow tempos. Coarser beats are preferred within each slot.
      final subdivisions = pow(
        2,
        max(0, (log(grid.period / min(0.04, width / 3)) / ln2).ceil()),
      );
      final step = grid.period / subdivisions;
      final used = <OnsetCandidate>{};
      for (var slot = 0; slot < quota; slot++) {
        final lower = start + slot * width;
        // Reserve the hand transition into the next window, even if the song
        // has only a very short fractional final window.
        final upper = min(
          start + (slot + 1) * width,
          end < duration ? end - min(0.11, (end - start) * 0.1) : end,
        );
        final center = (lower + upper) / 2;
        List<int> hands(double t) => [
          for (var h = 0; h < 2; h++)
            if (busyUntil[h] <= t + 1e-8) h,
        ];
        final audible = section
            .where(
              (c) =>
                  !used.contains(c) &&
                  c.note.time >= lower &&
                  c.note.time < upper &&
                  hands(c.note.time).isNotEmpty,
            )
            .toList();
        double cost(OnsetCandidate c) =>
            (c.note.time - center).abs() / width +
            grid.rank(c.note.time) * 0.06 -
            log(1 + c.strength) * 0.015;
        final candidate = result.isEmpty && audible.contains(input.first)
            ? input.first
            : audible.isEmpty
            ? null
            : audible.reduce((a, b) => cost(a) <= cost(b) ? a : b);
        late double time;
        if (candidate != null) {
          used.add(candidate);
          time = candidate.note.time;
        } else {
          final first = ((lower - grid.origin) / step).ceil();
          final last = ((upper - grid.origin) / step).ceil() - 1;
          final times =
              [for (var i = first; i <= last; i++) grid.origin + i * step]
                  .where((t) => t >= lower && t < upper && hands(t).isNotEmpty)
                  .toList();
          double gridCost(double t) =>
              (t - center).abs() / width + grid.rank(t) * 0.07;
          if (times.isEmpty) {
            throw StateError('No playable metrical slot at $lower');
          }
          time = times.reduce((a, b) => gridCost(a) <= gridCost(b) ? a : b);
        }
        var length = min(
          AnalyzedNote.maximumHoldDuration,
          candidate?.note.duration ?? 0.0,
        );
        // A second overlapping sustain becomes a tap: one thumb must remain
        // available for the fixed pace, while the first vocal keeps its tail.
        if (time < holdBusyUntil || length < AnalyzedNote.minimumHoldDuration) {
          length = 0;
        }
        final preferred = candidate?.note.lane ?? slot % 4;
        int add(double length) {
          if (laneBag.isEmpty) laneBag.addAll([0, 1, 2, 3]);
          final free = [
            for (final h in hands(time)) h * 2,
            for (final h in hands(time)) h * 2 + 1,
          ];
          var lanes = free.where(laneBag.contains).toList();
          if (lanes.isEmpty) lanes = free;
          final lane = lanes.reduce(
            (a, b) => (a - preferred).abs() <= (b - preferred).abs() ? a : b,
          );
          final note = AnalyzedNote(time, lane, duration: length);
          result.add(note);
          busyUntil[lane ~/ 2] =
              (note.isLong ? note.endTime : note.time) +
              AnalyzedNote.holdReleaseTolerance;
          if (note.isLong) holdBusyUntil = busyUntil[lane ~/ 2];
          laneBag.remove(lane);
          return lane;
        }

        add(length);
        // A strong measured chord may consume two adjacent slots, one per
        // hand. START remains single and ordinary fallback beats stay single.
        if (candidate?.doubleAccent == true &&
            length == 0 &&
            slot > 0 &&
            slot + 1 < quota &&
            width < 0.5 &&
            time > lower + width * 0.45 &&
            hands(time).isNotEmpty) {
          add(0);
          slot++;
        }
      }
    }
    return result;
  }
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
