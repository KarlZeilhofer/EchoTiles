class AnalyzedNote {
  final double time;
  final int lane;
  const AnalyzedNote(this.time, this.lane);

  Map<String, Object> toJson() => {'time': time, 'lane': lane};
  factory AnalyzedNote.fromJson(Map<String, dynamic> json) => AnalyzedNote(
    (json['time'] as num).toDouble(),
    (json['lane'] as num).toInt(),
  );
}

class SongAnalysis {
  static const version = 1;
  final double duration;
  final double bpm;
  final List<AnalyzedNote> notes;
  const SongAnalysis({
    required this.duration,
    required this.bpm,
    required this.notes,
  });

  Map<String, Object> toJson() => {
    'version': version,
    'duration': duration,
    'bpm': bpm,
    'notes': notes.map((n) => n.toJson()).toList(),
  };

  factory SongAnalysis.fromJson(Map<String, dynamic> json) {
    if (json['version'] != version) throw const FormatException('Old analysis');
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
    return SongAnalysis(
      duration: duration,
      bpm: bpm,
      notes: _distributeLanes(notes),
    );
  }

  // Balance each group of four notes while preferring the lane suggested by
  // spectral brightness. Apply at the shared decoding boundary so existing
  // saved charts benefit too, without repeating the expensive audio analysis.
  // Already-balanced charts retain their layout when loaded again.
  static List<AnalyzedNote> _distributeLanes(List<AnalyzedNote> notes) {
    final available = <int>{};
    final result = <AnalyzedNote>[];
    var previous = -1;
    for (final note in notes) {
      if (available.isEmpty) available.addAll([0, 1, 2, 3]);
      final candidates = available.where((lane) => lane != previous);
      int cost(int lane) =>
          (lane - note.lane).abs() * 8 +
          (previous < 0 ? 0 : (lane - previous).abs());
      final lane = candidates.reduce((a, b) => cost(a) <= cost(b) ? a : b);
      result.add(AnalyzedNote(note.time, lane));
      available.remove(lane);
      previous = lane;
    }
    return result;
  }
}
