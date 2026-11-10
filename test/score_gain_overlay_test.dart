import 'dart:io';
import 'dart:ui' as ui;

import 'package:echotiles/widgets/score_gain_overlay.dart';
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
  });
  test('tap gain starts above contact, flies to score, then expires', () {
    final gold = ScoreGainController();
    const target = Offset(200, 45);
    gold.begin(1, 102, const Offset(100, 400));
    final gain = gold.gains.single;
    expect(gain.position(target), const Offset(100, 334));
    gold.advance(0.6);
    expect(gain.position(target).dy, lessThan(334));
    expect(gain.position(target).dx, greaterThan(100));
    gold.advance(0.4);
    expect(gain.position(target), target);
    gold.advance(0.2);
    expect(gold.gains, isEmpty);
    gold.dispose();
  });

  test(
    'slider gain counts live, remains above contact and includes release bonus',
    () {
      final gold = ScoreGainController();
      gold.begin(2, 104, const Offset(300, 400), holding: true);
      gold.advance(3);
      gold.add(2, 660);
      expect(gold.gains.single.points, 764);
      expect(gold.gains.single.flight, 0);
      gold.move(2, const Offset(305, 410));
      expect(gold.gains.single.origin, const Offset(305, 410));
      gold.release(2, bonus: 150);
      expect(gold.gains.single.points, 914);
      gold.add(2, 99);
      expect(
        gold.gains.single.points,
        914,
        reason: 'Released gain must stop counting',
      );
      gold.advance(1.2);
      expect(gold.gains, isEmpty);
      gold.dispose();
    },
  );

  testWidgets(
    'gold overlay paints without blocking taps and animates after a hold',
    (tester) async {
      final gold = ScoreGainController();
      final boundary = GlobalKey();
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              backgroundColor: const Color(0xFF101516),
              body: Stack(
                children: [
                  Positioned(
                    top: 30,
                    left: 0,
                    right: 0,
                    child: const Text(
                      '1 204',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontFamily: 'Fredoka',
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                    ),
                  ),
                  Positioned.fill(
                    child: ScoreGainOverlay(
                      controller: gold,
                      scoreTarget: () => const Offset(400, 55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      gold.begin(1, 102, const Offset(240, 360));
      gold.begin(2, 428, const Offset(540, 360), holding: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(const Offset(240, 360));
      expect(taps, 1);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/echotiles-gold-preview.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      gold.release(2, bonus: 150);
      await tester.pump(const Duration(milliseconds: 600));
      expect(gold.gains.any((g) => g.flight > 0), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(gold.gains, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      gold.dispose();
    },
  );
}
