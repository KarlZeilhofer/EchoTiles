import 'analyzed_note.dart';

/// Measured audio evidence, kept independently of either playable chart.
class OnsetCandidate {
  final AnalyzedNote note;
  final double strength;
  final bool doubleAccent;
  const OnsetCandidate(
    this.note, {
    this.strength = 1,
    this.doubleAccent = false,
  });

  factory OnsetCandidate.fromJson(Map<String, dynamic> json) => OnsetCandidate(
    AnalyzedNote.fromJson(json),
    strength: (json['strength'] as num).toDouble(),
    doubleAccent: json['doubleAccent'] as bool,
  );

  Map<String, Object> toJson() => {
    ...note.toJson(),
    'strength': strength,
    'doubleAccent': doubleAccent,
  };
}
