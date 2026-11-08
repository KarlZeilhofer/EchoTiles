import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/song_catalog.dart';
import 'package:echotiles/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('START hits the real first tile once, even at audio time zero', (
    tester,
  ) async {
    await StorageService.init();
    await AudioService.instance.init();
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final song = SongCatalog.defaultSongs.first;
    Offset point(int lane) => Offset(
      size.width * (lane + 0.5) / 4,
      size.height * RhythmTimeline.targetLineFactor,
    );
    Future<void> open(SongAnalysis analysis) async {
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
    }

    Future<void> finish() async {
      final timeout = Stopwatch()..start();
      while (find.textContaining('SONG COMPLETED').evaluate().isEmpty) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        if (timeout.elapsed > const Duration(seconds: 8)) {
          fail('First tile was not consumed by START');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    for (final onset in [0.0, 0.5]) {
      await open(
        SongAnalysis(duration: 1.1, bpm: 120, notes: [AnalyzedNote(onset, 2)]),
      );
      await tester.tapAt(point(2));
      await tester.pump();
      expect(find.text('102'), findsOneWidget);
      await finish(); // No second tap on a duplicate first tile.
    }
    await open(
      const SongAnalysis(
        duration: 1.6,
        bpm: 120,
        notes: [AnalyzedNote(0.1, 1, duration: 1.2)],
      ),
    );
    final hold = await tester.startGesture(point(1), pointer: 70);
    await tester.pump();
    expect(find.text('102'), findsOneWidget);
    while (true) {
      await tester.pump();
      expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
      final pos = await AudioService.instance.getCurrentPosition();
      if (pos != null && pos.inMilliseconds >= 1320) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(
      int.parse(
        tester.widget<Text>(find.byKey(const ValueKey('game-score'))).data!,
      ),
      lessThanOrEqualTo(366),
    );
    await hold.up();
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('game-score'))).data,
      '516', // 102 attack + 1.2 seconds * 220 + 150 on release.
    );
    await finish();

    // A dense source becomes a chart that can be completed with two thumbs.
    final twoThumbs = SongAnalysis.fromJson({
      'version': 3,
      'duration': 3,
      'bpm': 120,
      'notes': [
        const AnalyzedNote(0.4, 0, duration: 1.8),
        const AnalyzedNote(0.6, 1, duration: 1.8),
        const AnalyzedNote(0.8, 2),
        const AnalyzedNote(0.9, 3, duration: 1.1),
        const AnalyzedNote(2.4, 2),
      ].map((n) => n.toJson()).toList(),
    });
    expect(twoThumbs.notes.map((n) => n.time), [0.4, 0.6, 2.4]);
    expect(twoThumbs.notes[0].lane ~/ 2, 0);
    expect(twoThumbs.notes[1].lane ~/ 2, 1);
    await open(twoThumbs);
    final left = await tester.startGesture(
      point(twoThumbs.notes[0].lane),
      pointer: 80,
    );
    await tester.pump();
    Future<void> waitAt(double time) async {
      final deadline = Stopwatch()..start();
      while (true) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        final pos = await AudioService.instance.getCurrentPosition();
        if (pos != null && pos.inMicroseconds / 1000000 >= time) return;
        if (deadline.elapsed > const Duration(seconds: 8)) {
          fail('Playback stalled');
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    }

    await waitAt(0.6);
    final right = await tester.startGesture(
      point(twoThumbs.notes[1].lane),
      pointer: 81,
    );
    await waitAt(2.22);
    await left.up();
    await waitAt(2.42);
    await right.up();
    await tester.tapAt(point(twoThumbs.notes[2].lane));
    await finish();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
