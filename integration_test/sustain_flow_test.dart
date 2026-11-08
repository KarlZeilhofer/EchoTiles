import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/analysis_service.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('one-second slider minimum and original forgiving hold release', (
    tester,
  ) async {
    await StorageService.init();
    await AudioService.instance.init();
    const rate = 22050;
    const samples = rate * 4;
    final bytes = ByteData(44 + samples * 2);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + samples * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, rate, Endian.little);
    bytes.setUint32(28, rate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, samples * 2, Endian.little);
    const tones = [
      (0.5, 0.6, 440.0, 0.003),
      (1.6, 1.3, 660.0, 0.001),
      (3.3, 0.06, 880.0, 0.6),
    ];
    for (var i = 0; i < samples; i++) {
      final time = i / rate;
      var value = 0.0;
      for (final (start, duration, frequency, gain) in tones) {
        final phase = time - start;
        if (phase >= 0 && phase < duration) {
          value +=
              gain *
              min(1.0, phase / 0.01) *
              min(1.0, (duration - phase) / 0.02) *
              sin(2 * pi * frequency * phase);
        }
      }
      bytes.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
    }
    final temp = await getTemporaryDirectory();
    final wav = File('${temp.path}/sustain-test.wav');
    await wav.writeAsBytes(bytes.buffer.asUint8List());
    final song = SongItem(
      id: 'integration_sustains',
      title: 'Sustains',
      artist: 'Test',
      assetAudio: wav.path,
      bpm: 120,
      notesCount: 3,
    );
    final analysis = await AnalysisService.instance.analyze(song);
    final holds = analysis.notes.where((n) => n.isLong).toList();
    expect(holds.length, 1);
    expect(holds[0].duration, closeTo(1.3, 0.1));
    expect(analysis.notes.first.isLong, isFalse);
    expect(
      analysis.notes.length,
      3,
      reason: 'Quiet sustained notes must not acquire phantom taps',
    );
    debugPrint(
      'Quiet chart: ${analysis.notes.map((n) => n.toJson()).toList()}',
    );
    expect(analysis.notes.any((n) => !n.isLong), isTrue);
    debugPrint(
      'Detected hold lengths: ${holds.map((n) => n.duration).toList()}',
    );

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    Offset point(int lane) => Offset(
      size.width * (lane + 0.5) / 4,
      size.height * RhythmTimeline.targetLineFactor,
    );
    Future<void> openGame() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            song: song,
            analysis: analysis,
            appTheme: AppThemes.fromName('amoled'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(point(analysis.notes.first.lane));
      await tester.pump();
    }

    Future<void> waitForPosition(double time) async {
      final timeout = Stopwatch()..start();
      while (true) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        final position = await AudioService.instance.getCurrentPosition();
        if (position != null && position.inMicroseconds / 1000000 >= time) {
          return;
        }
        if (timeout.elapsed > const Duration(seconds: 12)) {
          fail('Playback stalled before $time');
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    }

    await openGame();
    var pointer = 100;
    var pauseTested = false;
    for (final note in analysis.notes.skip(1)) {
      await waitForPosition(note.time - 0.02);
      if (!note.isLong) {
        await tester.tapAt(point(note.lane));
      } else {
        var gesture = await tester.startGesture(
          point(note.lane),
          pointer: pointer++,
        );
        await tester.pump();
        if (!pauseTested) {
          await tester.tap(find.byIcon(Icons.pause_rounded));
          await tester.pumpAndSettle();
          await tester.tap(find.text('RESUME'));
          while (find.text('PAUSED').evaluate().isNotEmpty) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          pauseTested = true;
        }
        await waitForPosition(note.endTime - 0.03);
        await gesture.up();
      }
      await tester.pump();
    }
    final completion = Stopwatch()..start();
    while (find.textContaining('SONG COMPLETED').evaluate().isEmpty) {
      await tester.pump();
      expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
      if (completion.elapsed > const Duration(seconds: 5)) {
        fail('Holds did not complete');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull);

    // Original F-Droid behavior: a short tap on a slider clears it and
    // gives no full-hold bonus, but never ends an otherwise correct run.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await openGame();
    for (final note in analysis.notes.skip(1)) {
      await waitForPosition(note.time);
      await tester.tapAt(point(note.lane));
      await tester.pump();
      expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
    }
    completion.reset();
    while (find.textContaining('SONG COMPLETED').evaluate().isEmpty) {
      await tester.pump();
      expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
      if (completion.elapsed > const Duration(seconds: 5)) {
        fail('Early slider release incorrectly stopped the run');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await AnalysisService.instance.remove(song);
    await wav.delete();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
