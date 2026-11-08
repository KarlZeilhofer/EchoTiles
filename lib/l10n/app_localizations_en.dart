// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get tagline => 'TAP TO THE BEAT';

  @override
  String get addSong => 'ADD SONG';

  @override
  String get songName => 'Song Name';

  @override
  String get songNameHint => 'Enter song title';

  @override
  String get chooseAudio => 'Choose Audio';

  @override
  String get cancel => 'CANCEL';

  @override
  String get add => 'ADD';

  @override
  String get addYourSong => 'Add your song';

  @override
  String get howToPlay => 'How to play';

  @override
  String get noSongsYet => 'NO SONGS YET';

  @override
  String get noSongsHint => 'Add your audio files below to start playing!';

  @override
  String bestScoreShort(int score) {
    return 'BEST: $score';
  }

  @override
  String get customArtist => 'Custom';

  @override
  String get settingsTitle => 'SETTINGS';

  @override
  String get hapticsSection => 'HAPTICS';

  @override
  String get hapticFeedback => 'Haptic Feedback';

  @override
  String get themeSection => 'THEME';

  @override
  String get languageSection => 'LANGUAGE';

  @override
  String get systemDefault => 'System default';

  @override
  String get langEnglish => 'English';

  @override
  String get langItalian => 'Italiano';

  @override
  String get resetHighScores => 'RESET HIGH SCORES';

  @override
  String get resetScoresTitle => 'Reset Scores?';

  @override
  String get resetScoresMessage =>
      'Are you sure you want to reset all saved high scores and stars?';

  @override
  String get reset => 'RESET';

  @override
  String get themeNameClean => 'Clean';

  @override
  String get themeNameDark => 'Dark';

  @override
  String get themeNameAmoled => 'AMOLED Dark';

  @override
  String get themeNameForest => 'Forest';

  @override
  String get themeNameOcean => 'Ocean';

  @override
  String get themeNameSunset => 'Sunset';

  @override
  String get paused => 'PAUSED';

  @override
  String get resume => 'RESUME';

  @override
  String get home => 'HOME';

  @override
  String get songCompleted => 'SONG COMPLETED!';

  @override
  String get outOfRhythm => 'OUT OF RHYTHM!';

  @override
  String get score => 'Score';

  @override
  String get bestScore => 'Best Score';

  @override
  String get playAgain => 'PLAY AGAIN';

  @override
  String get tryAgain => 'TRY AGAIN';

  @override
  String get start => 'START';

  @override
  String get qualityPerfect => 'PERFECT!';

  @override
  String get qualityGreat => 'GREAT!';

  @override
  String get qualityGood => 'GOOD';

  @override
  String get qualityMiss => 'MISS!';

  @override
  String comboLabel(int combo) {
    return '${combo}x COMBO';
  }

  @override
  String get howToPlayTitle => 'HOW TO PLAY';

  @override
  String get singleTapTitle => 'SINGLE TAP TILES';

  @override
  String get singleTapSubtitle =>
      'Tap each tile right as it hits the bottom line.';

  @override
  String get singleTapPoint1 =>
      'Tap the visible tile in its lane, just like the original F-Droid game.';

  @override
  String get singleTapPoint2 =>
      'A tile overlapping the judgment line gives a PERFECT rating.';

  @override
  String get singleTapPoint3 => 'A single tap clears the tile immediately.';

  @override
  String get holdTilesTitle => 'HOLD TILES';

  @override
  String get holdTilesSubtitle =>
      'Identified by the circle head and straight line.';

  @override
  String get holdTilesPoint1 =>
      'Only notes lasting at least 1 second become hold tiles.';

  @override
  String get holdTilesPoint2 =>
      'Keep holding for bonus points. Releasing early does not end your run.';

  @override
  String get holdTilesPoint3 =>
      'Hold until the tail reaches the line for the full bonus.';

  @override
  String get avoidMistakesTitle => 'AVOID MISTAKES';

  @override
  String get avoidMistakesSubtitle => 'Keep your song streak alive.';

  @override
  String get avoidMistakesPoint1 =>
      'Never tap an empty lane where no tile is passing.';

  @override
  String get avoidMistakesPoint2 =>
      'Don\'t let tiles scroll past the bottom without touching them.';

  @override
  String get avoidMistakesPoint3 =>
      'Play with multiple fingers for fast BPM songs.';

  @override
  String get judgmentLine => 'JUDGMENT LINE';

  @override
  String get tap => 'TAP';

  @override
  String get chargingCombo => 'CHARGING COMBO';

  @override
  String get missTriggerTitle => 'MISS TRIGGER';

  @override
  String get missTriggerText =>
      'Tapping empty spaces or letting tiles fall through ends your run immediately.';

  @override
  String get gotItLetsPlay => 'GOT IT, LET\'S PLAY!';

  @override
  String get analyzeNow => 'Analyze now';

  @override
  String get analyzingSong => 'Analyzing notes and rhythm…';

  @override
  String get analysisHint =>
      'Analyze this song before playing. Results are saved on this device.';

  @override
  String get analysisReady => 'Rhythm ready';

  @override
  String get analysisFailed => 'Analysis failed. Try another audio file.';

  @override
  String get noBeatsFound => 'No distinct notes or beats found.';

  @override
  String get startRhythm =>
      'Tap START. Tiles arrive with the music after a short lead-in.';

  @override
  String get rhythmDifficulty =>
      'Later in the song, tiles scroll faster and more detected notes are included.';

  @override
  String get analyzeHoldsHint => 'Analyze again to detect long notes.';
}
