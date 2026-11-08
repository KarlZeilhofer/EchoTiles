import 'dart:io';
import 'dart:typed_data';

import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/song_catalog.dart';
import 'package:echotiles/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('slider release deadline, final note, pause and late input', (
    tester,
  ) async {
    await StorageService.init();
    await AudioService.instance.init();
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final point = Offset(
      size.width / 8,
      size.height * RhythmTimeline.targetLineFactor,
    );
    const note = AnalyzedNote(0.2, 0, duration: 1);
    // A valid, silent PCM WAV whose audio really ends with the final slider.
    const samples = 26460; // 1.2 seconds at 22050 Hz.
    final wav = ByteData(44 + samples * 2);
    void ascii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        wav.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    wav.setUint32(4, 36 + samples * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little);
    wav.setUint16(20, 1, Endian.little);
    wav.setUint16(22, 1, Endian.little);
    wav.setUint32(24, 22050, Endian.little);
    wav.setUint32(28, 44100, Endian.little);
    wav.setUint16(32, 2, Endian.little);
    wav.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    wav.setUint32(40, samples * 2, Endian.little);
    final directory = await getTemporaryDirectory();
    final audio = File('${directory.path}/hold-release-test.wav');
    await audio.writeAsBytes(wav.buffer.asUint8List());
    final endSong = SongItem(
      id: 'release-test',
      title: 'Release',
      artist: 'Test',
      assetAudio: audio.path,
      bpm: 120,
      notesCount: 1,
    );

    Future<void> open({bool audioEnds = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            song: audioEnds ? endSong : SongCatalog.defaultSongs.first,
            // The held note ends with the chart: no automatic victory may hide
            // an overheld last slider, even after the actual audio completes.
            analysis: const SongAnalysis(
              duration: 1.2,
              bpm: 120,
              notes: [note],
            ),
            appTheme: AppThemes.fromName('amoled'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    Future<void> waitAt(double seconds) async {
      final timeout = Stopwatch()..start();
      while (true) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        expect(find.textContaining('SONG COMPLETED'), findsNothing);
        final pos = await AudioService.instance.getCurrentPosition();
        if (pos != null && pos.inMicroseconds / 1000000 >= seconds) return;
        if (timeout.elapsed > const Duration(seconds: 6)) {
          fail('Playback stalled');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    // A normal release just after the tail passes the line wins the last note.
    await open();
    var gesture = await tester.startGesture(point, pointer: 20);
    await waitAt(note.endTime + 0.02);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('SONG COMPLETED'), findsOneWidget);
    expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
    await close();

    // Continuing to hold loses without needing any additional pointer event.
    await open(audioEnds: true);
    gesture = await tester.startGesture(point, pointer: 21);
    await waitAt(1.1);
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
    expect(find.text('PAUSED'), findsOneWidget);
    await tester.tap(find.text('RESUME'));
    final timeout = Stopwatch()..start();
    while (find.textContaining('OUT OF RHYTHM').evaluate().isEmpty) {
      await tester.pump();
      expect(find.textContaining('SONG COMPLETED'), findsNothing);
      if (timeout.elapsed > const Duration(seconds: 5)) {
        fail('Overhold did not lose');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final score = tester
        .widget<Text>(find.byKey(const ValueKey('game-score')))
        .data;
    expect(score, '322'); // Only attack + hold time, no completion bonus.
    await gesture.up();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('game-score'))).data,
      score,
    );
    await close();

    // Late input must not escape a deadline between rendered frames. Stall
    // pumping, then deliver up/move/cancel before requesting the next frame.
    for (final action in ['up', 'move', 'cancel']) {
      await open();
      gesture = await tester.startGesture(point, pointer: 30);
      await waitAt(1.1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      switch (action) {
        case 'up':
          await gesture.up();
        case 'move':
          await gesture.moveTo(Offset(size.width * 0.4, point.dy));
        case 'cancel':
          await gesture.cancel();
      }
      await tester.pump();
      expect(
        find.textContaining('OUT OF RHYTHM'),
        findsOneWidget,
        reason: action,
      );
      expect(find.textContaining('SONG COMPLETED'), findsNothing);
      if (action == 'move') await gesture.up();
      await close();
    }
    await audio.delete();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
