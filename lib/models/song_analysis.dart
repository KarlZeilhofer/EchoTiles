class AnalyzedNote {
  final double time;
  final int lane;
  final double duration;
  const AnalyzedNote(this.time, this.lane, {this.duration = 0});
  bool get isLong => duration >= 0.4;
  double get endTime => time + duration;

  Map<String, Object> toJson() => {
    'time': time,
    'lane': lane,
    'duration': duration,
  };
  factory AnalyzedNote.fromJson(Map<String, dynamic> json) => AnalyzedNote(
    (json['time'] as num).toDouble(),
    (json['lane'] as num).toInt(),
    duration: (json['duration'] as num?)?.toDouble() ?? 0,
  );
}

class SongAnalysis {
  static const version = 2;
  final double duration;
  final double bpm;
  final int analysisVersion;
  final List<AnalyzedNote> notes;
  const SongAnalysis({
    required this.duration,
    required this.bpm,
    required this.notes,
    this.analysisVersion = version,
  });

  Map<String, Object> toJson() => {
    'version': analysisVersion,
    'duration': duration,
    'bpm': bpm,
    'notes': notes.map((n) => n.toJson()).toList(),
  };

  factory SongAnalysis.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != version) {
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
    return SongAnalysis(
      duration: duration,
      bpm: bpm,
      notes: _distributeLanes(notes),
      analysisVersion: json['version'] as int,
    );
  }

  // Balance each group of four notes while preferring the lane suggested by
  // spectral brightness. Apply at the shared decoding boundary so existing
  // saved charts benefit too, without repeating the expensive audio analysis.
  // Already-balanced charts retain their layout when loaded again.
  static List<AnalyzedNote> _distributeLanes(List<AnalyzedNote> notes) {
    final available = <int>{};
    final result = <AnalyzedNote>[];
    final busyUntil = List<double>.filled(4, 0);
    final lastNote = List<int>.filled(4, -1);
    var previous = -1;
    for (final note in notes) {
      if (available.isEmpty) available.addAll([0, 1, 2, 3]);
      var free = [
        for (var lane = 0; lane < 4; lane++)
          if (busyUntil[lane] <= note.time + 1e-6) lane,
      ];
      if (free.isEmpty) {
        // Preserve every onset if all fingers are occupied: release the hold
        // ending soonest before this new note, rather than overlap one lane.
        final lane = [
          0,
          1,
          2,
          3,
        ].reduce((a, b) => busyUntil[a] <= busyUntil[b] ? a : b);
        final index = lastNote[lane];
        final old = result[index];
        final length = (note.time - old.time - 0.08).clamp(0.0, old.duration);
        result[index] = AnalyzedNote(
          old.time,
          old.lane,
          duration: length >= 0.4 ? length : 0,
        );
        free = [lane];
      }
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
      lastNote[lane] = result.length - 1;
      busyUntil[lane] = note.isLong ? note.endTime + 0.08 : note.time;
      available.remove(lane);
      previous = lane;
    }
    return result;
  }
}
