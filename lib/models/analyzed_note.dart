class AnalyzedNote {
  final double time;
  final int lane;
  final double duration;
  const AnalyzedNote(this.time, this.lane, {this.duration = 0});
  static const minimumHoldDuration = 1.0;
  static const maximumHoldDuration = 4.0;
  static const holdReleaseTolerance = 0.10;
  bool get isLong => duration >= minimumHoldDuration;
  double get endTime => time + duration;
  bool isReleaseLate(double time) => time > endTime + holdReleaseTolerance;

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
