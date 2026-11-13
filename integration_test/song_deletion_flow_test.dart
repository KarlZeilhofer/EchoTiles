import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:echotiles/main.dart';
import 'package:echotiles/models/game_models.dart';
import 'package:echotiles/models/song_analysis.dart';
import 'package:echotiles/screens/game_screen.dart';
import 'package:echotiles/services/analysis_service.dart';
import 'package:echotiles/services/audio_service.dart';
import 'package:echotiles/services/storage_service.dart';
import 'package:echotiles/widgets/delete_song_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'song and analysis survive trash tap and cancel; full slider removes only library entry and cache',
    (tester) async {
      await StorageService.init();
      await AudioService.instance.init();
      const id = 'custom_deletion_test';
      final directory = await getTemporaryDirectory();
      final audio = File('${directory.path}/delete-confirmation.wav');
      final bytes = ByteData(44 + 22050 * 2);
      void ascii(int offset, String text) {
        for (var i = 0; i < text.length; i++) {
          bytes.setUint8(offset + i, text.codeUnitAt(i));
        }
      }

      ascii(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      ascii(8, 'WAVE');
      ascii(12, 'fmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 22050, Endian.little);
      bytes.setUint32(28, 44100, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      ascii(36, 'data');
      bytes.setUint32(40, 44100, Endian.little);
      await audio.writeAsBytes(bytes.buffer.asUint8List());
      final song = SongItem(
        id: id,
        title: 'Delete confirmation test',
        artist: 'Test',
        assetAudio: audio.path,
        bpm: 120,
        notesCount: 1,
      );
      await StorageService.removeCustomSong(id);
      await AnalysisService.instance.remove(song);
      await StorageService.addCustomSong(song);
      final support = await getApplicationSupportDirectory();
      final cache = File(
        '${support.path}/analysis/${base64Url.encode(utf8.encode(id))}.json',
      );
      await cache.parent.create(recursive: true);
      final stat = await audio.stat();
      await cache.writeAsString(
        jsonEncode({
          'version': SongAnalysis.version,
          'source': audio.path,
          'size': stat.size,
          'modified': stat.modified.millisecondsSinceEpoch,
          'duration': 1,
          'bpm': 120,
          'notes': [const AnalyzedNote(0.2, 0).toJson()],
          'candidates': [
            {
              ...const AnalyzedNote(0.2, 0).toJson(),
              'strength': 1,
              'doubleAccent': false,
            },
          ],
        }),
      );
      await tester.pumpWidget(const EchoTilesApp());
      await tester.pumpAndSettle();
      final trash = find.byKey(const ValueKey('delete-custom_deletion_test'));
      await tester.scrollUntilVisible(
        trash,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(trash);
      await tester.pumpAndSettle();
      expect(find.byType(DeleteSongDialog), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(StorageService.getCustomSongs().any((s) => s.id == id), isTrue);
      expect(await cache.exists(), isTrue);
      final thumb = find.byKey(const ValueKey('delete-slider-thumb'));
      final track = tester.getRect(find.byType(SlideToDelete));
      final start = tester.getCenter(thumb);
      final end = Offset(track.right - 29, start.dy);
      await tester.tapAt(end);
      await tester.drag(thumb, Offset((end.dx - start.dx) * 0.5, 0));
      await tester.pumpAndSettle();
      expect(StorageService.getCustomSongs().any((s) => s.id == id), isTrue);
      expect(await cache.exists(), isTrue);
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(StorageService.getCustomSongs().any((s) => s.id == id), isTrue);
      await tester.tap(trash);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(thumb));
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        StorageService.getCustomSongs().any((s) => s.id == id),
        isTrue,
        reason: 'Must wait for actual pointer release',
      );
      await gesture.up();
      final timeout = Stopwatch()..start();
      while (StorageService.getCustomSongs().any((s) => s.id == id) ||
          await cache.exists() ||
          find.byType(DeleteSongDialog).evaluate().isNotEmpty ||
          find.text(song.title).evaluate().isNotEmpty) {
        await tester.pump();
        if (timeout.elapsed > const Duration(seconds: 8)) {
          fail('Confirmed deletion did not finish');
        }
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      await tester.pumpAndSettle();
      expect(find.text(song.title), findsNothing);
      expect(await AnalysisService.instance.load(song), isNull);
      expect(await audio.exists(), isTrue);
      expect(await audio.length(), bytes.lengthInBytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await audio.delete();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
