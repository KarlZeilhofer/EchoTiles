import 'dart:io';
import 'dart:ui' as ui;

import 'package:echotiles/l10n/app_localizations.dart';
import 'package:echotiles/models/app_theme.dart';
import 'package:echotiles/widgets/delete_song_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'Fredoka',
    )..addFont(rootBundle.load('assets/fonts/Fredoka.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'only a completed left-thumb drag followed by release confirms deletion',
    (tester) async {
      bool? result;
      var confirmations = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppThemes.fromName('amoled').toMaterialTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result = await showDialog<bool>(
                        context: context,
                        builder: (_) => DeleteSongDialog(
                          songTitle: 'My favourite song',
                          appTheme: AppThemes.fromName('amoled'),
                        ),
                      );
                      if (result == true) confirmations++;
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('My favourite song'), findsOneWidget);
      final slider = find.byType(SlideToDelete);
      final thumb = find.byKey(const ValueKey('delete-slider-thumb'));
      final track = tester.getRect(slider);
      final start = tester.getCenter(thumb);
      final end = Offset(track.right - 29, start.dy);

      // Tapping or dragging on the far end of the track is never confirmation.
      await tester.tapAt(end);
      await tester.dragFrom(track.center, Offset(track.width / 2, 0));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(confirmations, 0);
      await tester.drag(thumb, Offset((end.dx - start.dx) * 0.5, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(thumb), start);
      expect(result, isNull);

      var gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await tester.pump();
      expect(
        result,
        isNull,
        reason: 'Reaching the end without releasing is not confirmation',
      );
      await gesture.moveTo(Offset(start.dx + 35, start.dy));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(result, isNull);

      gesture = await tester.startGesture(start);
      await gesture.moveTo(end);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.getCenter(thumb), start);

      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/echotiles-delete-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });

      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(confirmations, 0);
      // Closing the dialog while a finger is still at the right end must
      // stay cancelled when that finger is subsequently lifted.
      result = null;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      gesture = await tester.startGesture(tester.getCenter(thumb));
      await gesture.moveTo(end);
      await tester.pump();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pump();
      expect(result, isFalse);
      expect(confirmations, 0);
      expect(find.text('Open'), findsOneWidget);
      result = null;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      gesture = await tester.startGesture(tester.getCenter(thumb));
      await gesture.moveTo(end);
      await tester.pump();
      expect(result, isNull);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(confirmations, 1);
      expect(find.byType(DeleteSongDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
