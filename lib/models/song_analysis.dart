import 'analyzed_note.dart';
import 'onset_candidate.dart';
import 'rhythm_chart_planner.dart';
import 'tile_variant.dart';

export 'analyzed_note.dart';

class SongAnalysis {
  static const version = 4;
  static const maxSimultaneousTiles = 2;
  static const thumbReleaseGap = 0.10;
  final double duration;
  final double bpm;
  final int analysisVersion;
  final List<AnalyzedNote> notes;
  final TileVariant variant;
  final List<OnsetCandidate>? candidates;
  final List<AnalyzedNote>? sourceNotes;
  const SongAnalysis({
    required this.duration,
    required this.bpm,
    required this.notes,
    this.analysisVersion = version,
    this.variant = TileVariant.a,
    this.candidates,
    this.sourceNotes,
  });

  Map<String, Object> toJson() => {
    'version': analysisVersion,
    'duration': duration,
    'bpm': bpm,
    'notes': (sourceNotes ?? notes).map((n) => n.toJson()).toList(),
    if (candidates != null)
      'candidates': candidates!.map((c) => c.toJson()).toList(),
  };

  factory SongAnalysis.fromJson(
    Map<String, dynamic> json, {
    TileVariant variant = TileVariant.a,
  }) {
    if (json['version'] != 1 &&
        json['version'] != 2 &&
        json['version'] != 3 &&
        json['version'] != version) {
      throw const FormatException('Old analysis');
    }
    final duration = (json['duration'] as num).toDouble();
    final bpm = (json['bpm'] as num).toDouble();
    final notes = (json['notes'] as List)
        .map((n) => AnalyzedNote.fromJson(Map<String, dynamic>.from(n as Map)))
        .toList();
    if (!duration.isFinite ||
        duration <= 0 ||
        !bpm.isFinite ||
        bpm < 0 ||
        notes.isEmpty ||
        notes.any(
          (n) =>
              !n.time.isFinite ||
              n.time < 0 ||
              n.time > duration ||
              !n.duration.isFinite ||
              n.duration < 0 ||
              n.endTime > duration + 0.001 ||
              n.lane < 0 ||
              n.lane > 3,
        )) {
      throw const FormatException('Invalid analysis');
    }
    for (var i = 1; i < notes.length; i++) {
      if (notes[i].time <= notes[i - 1].time) {
        throw const FormatException('Unsorted analysis');
      }
    }
    AnalyzedNote capped(AnalyzedNote n) => AnalyzedNote(
      n.time,
      n.lane,
      duration: n.duration > AnalyzedNote.maximumHoldDuration
          ? AnalyzedNote.maximumHoldDuration
          : n.duration,
    );
    final source = notes.map(capped).toList();
    final candidates = (json['candidates'] as List?)
        ?.map(
          (c) => OnsetCandidate.fromJson(Map<String, dynamic>.from(c as Map)),
        )
        .toList();
    if (candidates != null) {
      if (candidates.isEmpty) throw const FormatException('Empty candidates');
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        final n = c.note;
        if (!c.strength.isFinite ||
            c.strength <= 0 ||
            !n.time.isFinite ||
            n.time < 0 ||
            n.time > duration ||
            !n.duration.isFinite ||
            n.duration < 0 ||
            n.endTime > duration + 0.001 ||
            n.lane < 0 ||
            n.lane > 3 ||
            (i > 0 && n.time <= candidates[i - 1].note.time)) {
          throw const FormatException('Invalid onset candidates');
        }
        candidates[i] = OnsetCandidate(
          capped(n),
          strength: c.strength,
          doubleAccent: c.doubleAccent,
        );
      }
    }
    return SongAnalysis(
      duration: duration,
      bpm: bpm,
      notes: variant == TileVariant.b && candidates != null
          ? RhythmChartPlanner.plan(candidates, bpm, duration)
          : _distributeLanes(source),
      analysisVersion: json['version'] as int,
      variant: variant,
      candidates: candidates,
      sourceNotes: candidates == null ? null : source,
    );
  }

  // Each thumb owns its half: lanes 0/1 for left, 2/3 for right. Reserve the
  // entire hand during a hold, including a short release/transition margin.
  // Preserve full musical hold lengths and omit extra accents while both
  // thumbs are occupied instead of chopping every long vocal into short taps.
  static List<AnalyzedNote> _distributeLanes(List<AnalyzedNote> notes) {
    final available = <int>{};
    final result = <AnalyzedNote>[];
    final busyUntil = List<double>.filled(2, 0);
    var previous = -1;
    for (final note in notes) {
      final occupied = busyUntil.where((end) => end > note.time + 1e-6).length;
      if (occupied >= maxSimultaneousTiles) continue;
      if (available.isEmpty) available.addAll([0, 1, 2, 3]);
      final free = [
        for (var lane = 0; lane < 4; lane++)
          if (busyUntil[lane ~/ 2] <= note.time + 1e-6) lane,
      ];
      var candidates = free
          .where((lane) => available.contains(lane) && lane != previous)
          .toList();
      if (candidates.isEmpty) {
        candidates = free.where((lane) => lane != previous).toList();
      }
      if (candidates.isEmpty) candidates = free;
      int cost(int lane) =>
          (lane - note.lane).abs() * 8 +
          (previous < 0 ? 0 : (lane - previous).abs());
      final lane = candidates.reduce((a, b) => cost(a) <= cost(b) ? a : b);
      result.add(AnalyzedNote(note.time, lane, duration: note.duration));
      busyUntil[lane ~/ 2] =
          (note.isLong ? note.endTime : note.time) + thumbReleaseGap;
      available.remove(lane);
      previous = lane;
    }
    return result;
  }
}
