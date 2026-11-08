import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:echotiles/main.dart';
import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/analysis_service.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/song_catalog.dart';
import 'package:echotiles/services/storage_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native decoding, cached analysis, home and rhythm game', (
    tester,
  ) async {
    await StorageService.init();
    await AudioService.instance.init();
    final service = AnalysisService.instance;
    final temp = await getTemporaryDirectory();
    final wav = File('${temp.path}/rhythm-test.wav');
    const rate = 22050;
    const length = rate * 5;
    final data = ByteData(44 + length * 2);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    data.setUint32(4, 36 + length * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    data.setUint32(40, length * 2, Endian.little);
    for (var i = 0; i < length; i++) {
      final t = i / rate;
      final phase = (t - 0.5) % 0.5;
      final sample = t >= 0.5 && phase < 0.07
          ? 0.8 * sin(2 * pi * 440 * phase) * exp(-phase * 40)
          : 0.0;
      data.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
    }
    await wav.writeAsBytes(data.buffer.asUint8List());
    final song = SongItem(
      id: 'integration_clicks',
      title: 'Clicks',
      artist: 'Test',
      assetAudio: wav.path,
      bpm: 120,
      notesCount: 9,
    );
    final clicks = await service.analyze(song);
    expect(clicks.notes.length, inInclusiveRange(8, 10));
    expect(clicks.bpm, closeTo(120, 5));
    // Repeated identical tones must still populate every lane.
    expect(clicks.notes.map((n) => n.lane).toSet(), {0, 1, 2, 3});
    expect(
      clicks.notes.every(
        (n) =>
            (n.time - (0.5 + ((n.time - 0.5) / 0.5).round() * 0.5)).abs() <
            0.075,
      ),
      isTrue,
    );
    expect((await service.load(song))!.notes.length, clicks.notes.length);
    await service.remove(song);
    expect(await service.load(song), isNull);

    // Play the whole synthetic track using the real native playback position.
    // This exercises clock sync and touch judgment after the lead-in, rather
    // than only checking the ready/paused screens.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GameScreen(
          song: song,
          analysis: clicks,
          appTheme: AppThemes.fromName('amoled'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gameSize = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(
      Offset(
        gameSize.width * (clicks.notes.first.lane + 0.5) / 4,
        gameSize.height * RhythmTimeline.targetLineFactor,
      ),
    );
    await tester.pump();
    final playbackDeadline = Stopwatch()..start();
    for (final note in clicks.notes) {
      while (true) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        if (playbackDeadline.elapsed > const Duration(seconds: 15)) {
          fail('Playback did not reach note at ${note.time}s');
        }
        final position = await AudioService.instance.getCurrentPosition();
        if (position != null &&
            position.inMicroseconds / 1000000 >= note.time - 0.025) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await tester.tapAt(
        Offset(
          gameSize.width * (note.lane + 0.5) / 4,
          gameSize.height * RhythmTimeline.targetLineFactor,
        ),
      );
      await tester.pump();
    }
    while (find.textContaining('SONG COMPLETED').evaluate().isEmpty) {
      await tester.pump();
      expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
      if (playbackDeadline.elapsed > const Duration(seconds: 15)) {
        fail('Timed taps did not complete the track');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    // Silence must produce a useful error rather than a fabricated chart.
    for (var i = 44; i < data.lengthInBytes; i++) {
      data.setUint8(i, 0);
    }
    await wav.writeAsBytes(data.buffer.asUint8List());
    await expectLater(service.analyze(song), throwsA(isA<PlatformException>()));
    await wav.delete();

    // The bundled MP3 exercises Android's compressed-audio decoder as well.
    final bundled = SongCatalog.defaultSongs.first;
    final analysis = await service.analyze(bundled);
    expect(analysis.duration, greaterThan(30));
    expect(analysis.notes.length, greaterThan(30));
    expect(analysis.notes.map((n) => n.lane).toSet(), {0, 1, 2, 3});
    for (var i = 0; i < analysis.notes.length; i++) {
      final note = analysis.notes[i];
      if (!note.isLong) continue;
      final next = analysis.notes
          .skip(i + 1)
          .where((n) => n.lane == note.lane)
          .firstOrNull;
      if (next != null) {
        expect(note.endTime, lessThanOrEqualTo(next.time + 1e-6));
      }
    }
    debugPrint(
      'MP3 analysis: ${analysis.duration}s, ${analysis.notes.length} notes, ~${analysis.bpm} BPM',
    );

    await tester.pumpWidget(const EchoTilesApp());
    await tester.pumpAndSettle();
    expect(find.text('Analyze now'), findsOneWidget);
    expect(find.textContaining('Rhythm ready'), findsOneWidget);
    await tester.tap(find.text(bundled.title));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tap START'), findsOneWidget);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(
      Offset(
        size.width * (analysis.notes.first.lane + 0.5) / 4,
        size.height * RhythmTimeline.targetLineFactor,
      ),
    );
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    // Pause during the lead-in; real audio time must remain frozen.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('PAUSED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
