import 'package:echotiles/models/playback_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('jittery audio reports cannot teleport or rewind tiles', () {
    var now = 0.0;
    final clock = PlaybackClock(now: () => now)
      ..reset(10)
      ..resume();
    var previous = clock.position;
    for (var frame = 1; frame <= 600; frame++) {
      now = frame / 60;
      if (frame % 6 == 0) {
        final noise = frame % 12 == 0 ? -0.08 : 0.04;
        final before = clock.position;
        clock.synchronize(10 + now + noise);
        expect(clock.position, closeTo(before, 1e-9));
      }
      final position = clock.position;
      expect(position, greaterThan(previous));
      expect(
        position - previous,
        inInclusiveRange(0.9 / 60 - 1e-9, 1.1 / 60 + 1e-9),
      );
      previous = position;
    }
    expect(clock.position, closeTo(20, 0.10));
  });

  test('real drift converges smoothly without a position jump', () {
    var now = 0.0;
    final clock = PlaybackClock(now: () => now)
      ..reset(0)
      ..resume();
    now = 1;
    clock.synchronize(1.2);
    expect(clock.position, 1);
    now = 3;
    expect(clock.position, closeTo(3.2, 1e-9));
  });

  test('pause and resume preserve time through a long interruption', () {
    var now = 0.0;
    final clock = PlaybackClock(now: () => now)
      ..reset(-2)
      ..resume();
    now = 1;
    clock.pause();
    now = 20;
    clock.synchronize(100);
    expect(clock.position, -1);
    clock.resume();
    now = 21;
    expect(clock.position, 0);
    clock.reset(0.03);
    expect(clock.position, 0.03);
  });
}
