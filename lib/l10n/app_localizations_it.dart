// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get tagline => 'TOCCA A RITMO';

  @override
  String get addSong => 'AGGIUNGI CANZONE';

  @override
  String get songName => 'Nome canzone';

  @override
  String get songNameHint => 'Inserisci il titolo';

  @override
  String get chooseAudio => 'Scegli audio';

  @override
  String get cancel => 'ANNULLA';

  @override
  String get add => 'AGGIUNGI';

  @override
  String get addYourSong => 'Aggiungi la tua canzone';

  @override
  String get howToPlay => 'Come si gioca';

  @override
  String get noSongsYet => 'NESSUNA CANZONE';

  @override
  String get noSongsHint =>
      'Aggiungi i tuoi file audio qui sotto per iniziare a giocare!';

  @override
  String bestScoreShort(int score) {
    return 'RECORD: $score';
  }

  @override
  String get customArtist => 'Personalizzata';

  @override
  String get settingsTitle => 'IMPOSTAZIONI';

  @override
  String get hapticsSection => 'VIBRAZIONE';

  @override
  String get hapticFeedback => 'Feedback tattile';

  @override
  String get themeSection => 'TEMA';

  @override
  String get languageSection => 'LINGUA';

  @override
  String get systemDefault => 'Lingua di sistema';

  @override
  String get langEnglish => 'English';

  @override
  String get langItalian => 'Italiano';

  @override
  String get resetHighScores => 'AZZERA RECORD';

  @override
  String get resetScoresTitle => 'Azzerare i record?';

  @override
  String get resetScoresMessage =>
      'Vuoi davvero azzerare tutti i record e le stelle salvate?';

  @override
  String get reset => 'AZZERA';

  @override
  String get themeNameClean => 'Chiaro';

  @override
  String get themeNameDark => 'Scuro';

  @override
  String get themeNameAmoled => 'AMOLED Scuro';

  @override
  String get themeNameForest => 'Foresta';

  @override
  String get themeNameOcean => 'Oceano';

  @override
  String get themeNameSunset => 'Tramonto';

  @override
  String get paused => 'PAUSA';

  @override
  String get resume => 'RIPRENDI';

  @override
  String get home => 'HOME';

  @override
  String get songCompleted => 'CANZONE COMPLETATA!';

  @override
  String get outOfRhythm => 'FUORI RITMO!';

  @override
  String get score => 'Punteggio';

  @override
  String get bestScore => 'Record';

  @override
  String get playAgain => 'RIGIOCA';

  @override
  String get tryAgain => 'RIPROVA';

  @override
  String get start => 'START';

  @override
  String get qualityPerfect => 'PERFETTO!';

  @override
  String get qualityGreat => 'OTTIMO!';

  @override
  String get qualityGood => 'BUONO';

  @override
  String get qualityMiss => 'MANCATO!';

  @override
  String comboLabel(int combo) {
    return '${combo}x COMBO';
  }

  @override
  String get howToPlayTitle => 'COME SI GIOCA';

  @override
  String get singleTapTitle => 'TILES A TOCCO SINGOLO';

  @override
  String get singleTapSubtitle =>
      'Tocca ogni tile proprio quando raggiunge la linea in basso.';

  @override
  String get singleTapPoint1 =>
      'Tocca la tessera visibile nella sua corsia, come nel gioco originale F-Droid.';

  @override
  String get singleTapPoint2 =>
      'Una tessera sovrapposta alla linea dà una valutazione PERFECT.';

  @override
  String get singleTapPoint3 => 'Un singolo tocco rimuove subito il tile.';

  @override
  String get holdTilesTitle => 'TIENI PREMUTO I TILES';

  @override
  String get holdTilesSubtitle =>
      'Riconoscibili dalla testa circolare e dalla linea retta.';

  @override
  String get holdTilesPoint1 => 'Le tessere lunghe durano da 1 a 4 secondi.';

  @override
  String get holdTilesPoint2 =>
      'Tieni premuto per ottenere punti bonus. Rilasciare prima non termina la partita.';

  @override
  String get holdTilesPoint3 =>
      'Rilascia quando la coda raggiunge la linea. Tenere troppo a lungo termina la partita.';

  @override
  String get avoidMistakesTitle => 'EVITA GLI ERRORI';

  @override
  String get avoidMistakesSubtitle => 'Non interrompere la tua canzone.';

  @override
  String get avoidMistakesPoint1 =>
      'Non toccare mai una corsia vuota in cui non sta passando nessun tile.';

  @override
  String get avoidMistakesPoint2 =>
      'Non lasciare che i tile superino il fondo dello schermo senza toccarli.';

  @override
  String get avoidMistakesPoint3 =>
      'Usa più dita per le canzoni con BPM veloci.';

  @override
  String get judgmentLine => 'LINEA DI GIUDIZIO';

  @override
  String get tap => 'TOCCA';

  @override
  String get chargingCombo => 'COMBO IN CARICA';

  @override
  String get missTriggerTitle => 'ERRORE FATALE';

  @override
  String get missTriggerText =>
      'Toccare spazi vuoti o lasciare cadere i tile senza toccarli termina subito la partita.';

  @override
  String get gotItLetsPlay => 'CHIARO, GIOCHIAMO!';

  @override
  String get analyzeNow => 'Analizza ora';

  @override
  String get analyzingSong => 'Analisi delle note e del ritmo…';

  @override
  String get analysisHint =>
      'Premi Play. Le analisi mancanti o obsolete vengono preparate automaticamente.';

  @override
  String get analysisReady => 'Ritmo pronto';

  @override
  String get analysisFailed =>
      'Analisi non riuscita. Prova un altro file audio.';

  @override
  String get noBeatsFound => 'Nessuna nota o battito distinto trovato.';

  @override
  String get startRhythm =>
      'Tocca START per iniziare. Rilascia le tessere lunghe quando la coda raggiunge la linea.';

  @override
  String get rhythmDifficulty =>
      'La variante B mantiene un numero fisso in ogni sezione di 10 secondi.';

  @override
  String get analyzeHoldsHint =>
      'Analizza di nuovo per voci e suoni in dissolvenza.';

  @override
  String get tileVariantTitle => 'GENERAZIONE TESSERE';

  @override
  String get variantA => 'Variante A';

  @override
  String get variantB => 'Variante B';

  @override
  String get variantADescription => 'Selezione e accelerazione precedenti.';

  @override
  String get variantBDescription =>
      'Numero fisso di tessere ogni 10 secondi, integrate sul ritmo.';
}
