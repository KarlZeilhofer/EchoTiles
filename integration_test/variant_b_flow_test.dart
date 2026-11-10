import 'dart:convert';
import 'dart:io';

import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/main.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/models/rhythm_timeline.dart';
import 'package:echotiles/models/rhythm_chart_planner.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:echotiles/models/tile_variant.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/analysis_service.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/song_catalog.dart';
import 'package:echotiles/services/storage_service.dart';
import 'package:echotiles/widgets/score_gain_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'play automatically replaces old analysis; A/B share the new evidence',
    (tester) async {
      await StorageService.init();
      await AudioService.instance.init();
      await StorageService.setTileVariant(TileVariant.b);
      final service = AnalysisService.instance;
      final song = SongCatalog.defaultSongs.first;
      await service.remove(song);
      final support = await getApplicationSupportDirectory();
      final cache = File(
        '${support.path}/analysis/${base64Url.encode(utf8.encode(song.id))}.json',
      );
      await cache.parent.create(recursive: true);
      await cache.writeAsString(
        jsonEncode({
          'version': 3,
          'source': song.assetAudio,
          'duration': 215,
          'bpm': 124,
          'notes': [const AnalyzedNote(0.5, 0, duration: 10).toJson()],
        }),
      );
      expect(await service.load(song), isNull);
      await tester.pumpWidget(const EchoTilesApp());
      await tester.pumpAndSettle();
      expect(find.text('Analyze now'), findsNothing);
      await tester.tap(find.text(song.title));
      var sawProgress = false;
      final timeout = Stopwatch()..start();
      while (find.byType(GameScreen).evaluate().isEmpty) {
        await tester.pump();
        sawProgress |=
            find.text('Analyzing notes and rhythm…').evaluate().isNotEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
        if (timeout.elapsed > const Duration(seconds: 60)) {
          fail('Automatic analysis did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(sawProgress, isTrue);
      final b = tester.widget<GameScreen>(find.byType(GameScreen)).analysis;
      expect(b.variant, TileVariant.b);
      expect(b.notes.every((n) => n.duration <= 4), isTrue);
      for (var start = 0.0; start < b.duration; start += 10) {
        expect(
          b.notes.where((n) => n.time >= start && n.time < start + 10).length,
          RhythmChartPlanner.windowQuota(start, b.duration),
        );
      }
      final saved = await cache.readAsString();
      expect((jsonDecode(saved) as Map)['version'], SongAnalysis.version);
      expect(b.candidates, isNotEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('variant-b')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('variant-a')));
      await tester.pumpAndSettle();
      expect(StorageService.getTileVariant(), TileVariant.a);
      await tester.tap(find.byIcon(Icons.home_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(song.title));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GameScreen>(find.byType(GameScreen)).analysis.variant,
        TileVariant.a,
      );
      expect(
        await cache.readAsString(),
        saved,
        reason: 'Switching variants must reuse the audio analysis',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await StorageService.setTileVariant(TileVariant.b);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'B plays a two-thumb chord plus subdivisions beside a held slider',
    (tester) async {
      await StorageService.init();
      await AudioService.instance.init();
      const analysis = SongAnalysis(
        duration: 3.5,
        bpm: 120,
        variant: TileVariant.b,
        notes: [
          AnalyzedNote(0.2, 0),
          AnalyzedNote(1, 1, duration: 1),
          AnalyzedNote(1, 2),
          AnalyzedNote(1.5, 3),
          AnalyzedNote(2.2, 0),
          AnalyzedNote(3, 2),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GameScreen(
            song: SongCatalog.defaultSongs.first,
            analysis: analysis,
            appTheme: AppThemes.fromName('amoled'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      Offset point(int lane) => Offset(
        size.width * (lane + 0.5) / 4,
        size.height * RhythmTimeline.targetLineFactor,
      );
      Future<void> waitAt(double time) async {
        final timeout = Stopwatch()..start();
        while (true) {
          await tester.pump();
          expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
          final pos = await AudioService.instance.getCurrentPosition();
          if (pos != null && pos.inMicroseconds / 1000000 >= time) return;
          if (timeout.elapsed > const Duration(seconds: 8)) {
            fail('Playback stalled');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      await tester.tapAt(point(0));
      await waitAt(1);
      final left = await tester.startGesture(point(1), pointer: 80);
      await tester.pump();
      final gold = tester
          .widget<ScoreGainOverlay>(find.byType(ScoreGainOverlay))
          .controller;
      final gain = gold.gains.firstWhere((g) => g.id == 1);
      final attack = gain.points;
      await tester.tapAt(point(2));
      await waitAt(1.5);
      expect(gain.points, greaterThan(attack));
      expect(gain.holding, isTrue);
      expect(gain.origin, point(1));
      await tester.tapAt(point(3));
      await waitAt(2.02);
      await left.up();
      await tester.pump();
      expect(gain.holding, isFalse);
      expect(gain.points, greaterThanOrEqualTo(attack + 350));
      await waitAt(2.2);
      await tester.tapAt(point(0));
      await waitAt(3);
      await tester.tapAt(point(2));
      final timeout = Stopwatch()..start();
      while (find.textContaining('SONG COMPLETED').evaluate().isEmpty) {
        await tester.pump();
        expect(find.textContaining('OUT OF RHYTHM'), findsNothing);
        if (timeout.elapsed > const Duration(seconds: 5)) {
          fail('B chart did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
