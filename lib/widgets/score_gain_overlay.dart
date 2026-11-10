import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class ScoreGain {
  final int id;
  Offset origin;
  int points;
  bool holding;
  double age = 0;
  double? releasedAt;
  ScoreGain(this.id, this.origin, this.points, this.holding)
    : releasedAt = holding ? null : 0;

  double get flight => releasedAt == null
      ? 0
      : ((age - releasedAt! - 0.24) / 0.72).clamp(0.0, 1.0);
  bool get finished => releasedAt != null && age - releasedAt! >= 1.12;

  Offset position(Offset target) {
    final start = origin - const Offset(0, 66);
    final t = Curves.easeInOutCubic.transform(flight);
    final control = Offset(
      start.dx + (start.dx < target.dx ? -28 : 28),
      min(start.dy, target.dy) - 28,
    );
    return start * ((1 - t) * (1 - t)) +
        control * (2 * (1 - t) * t) +
        target * (t * t);
  }
}

/// Visual rewards mirror scoring; this controller never changes game points.
class ScoreGainController extends ChangeNotifier {
  final List<ScoreGain> gains = [];

  void begin(int id, int points, Offset origin, {bool holding = false}) {
    gains.add(ScoreGain(id, origin, points, holding));
    notifyListeners();
  }

  void add(int id, int points) {
    if (points == 0) return;
    final gain = gains.where((g) => g.id == id && g.holding).firstOrNull;
    if (gain == null) return;
    gain.points += points;
    notifyListeners();
  }

  void move(int id, Offset origin) {
    final gain = gains.where((g) => g.id == id && g.holding).firstOrNull;
    if (gain == null) return;
    gain.origin = origin;
    notifyListeners();
  }

  void release(int id, {int bonus = 0}) {
    final gain = gains.where((g) => g.id == id && g.holding).firstOrNull;
    if (gain == null) return;
    gain.points += bonus;
    gain.holding = false;
    gain.releasedAt = gain.age;
    notifyListeners();
  }

  void releaseAll() {
    for (final gain in gains.where((g) => g.holding)) {
      gain.holding = false;
      gain.releasedAt = gain.age;
    }
    notifyListeners();
  }

  void advance(double seconds) {
    for (final gain in gains) {
      gain.age += seconds;
    }
    gains.removeWhere((g) => g.finished);
    notifyListeners();
  }

  void clear() {
    gains.clear();
    notifyListeners();
  }
}

/// A separate, paint-only ticker keeps points flying after the last tile,
/// without rebuilding the game or participating in pointer hit testing.
class ScoreGainOverlay extends StatefulWidget {
  final ScoreGainController controller;
  final Offset? Function() scoreTarget;
  const ScoreGainOverlay({
    super.key,
    required this.controller,
    required this.scoreTarget,
  });

  @override
  State<ScoreGainOverlay> createState() => _ScoreGainOverlayState();
}

class _ScoreGainOverlayState extends State<ScoreGainOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _GoldPainter _painter;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _painter = _GoldPainter(widget.controller, () => widget.scoreTarget());
    _ticker = createTicker((elapsed) {
      final delta = elapsed - _last;
      _last = elapsed;
      widget.controller.advance(delta.inMicroseconds / 1000000);
    });
    widget.controller.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (widget.controller.gains.isNotEmpty && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (widget.controller.gains.isEmpty && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    _painter.disposeLabels();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(child: CustomPaint(painter: _painter)),
  );
}

class _GoldLabel {
  final int points;
  final int tick;
  final TextPainter fill;
  final TextPainter edge;
  _GoldLabel(this.points, this.tick)
    : fill = TextPainter(
        text: TextSpan(
          text: '+$points',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 25,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFE58C),
                  Color(0xFFFFFFE8),
                  Color(0xFFFFC536),
                  Color(0xFFFFDA63),
                  Color(0xFFEB9709),
                ],
                stops: [0, 0.32, 0.42, 0.70, 1],
              ).createShader(const Rect.fromLTWH(0, 0, 100, 32)),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
      edge = TextPainter(
        text: TextSpan(
          text: '+$points',
          style: TextStyle(
            fontFamily: 'Fredoka',
            fontSize: 25,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..color = const Color(0xFF824600)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
            shadows: const [Shadow(color: Color(0xB3FFC34A), blurRadius: 7)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  void dispose() {
    fill.dispose();
    edge.dispose();
  }
}

class _GoldPainter extends CustomPainter {
  final ScoreGainController controller;
  final Offset? Function() scoreTarget;
  final _labels = <int, _GoldLabel>{};
  _GoldPainter(this.controller, this.scoreTarget) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final target = scoreTarget() ?? Offset(size.width / 2, 48);
    final alive = controller.gains.map((g) => g.id).toSet();
    for (final id in _labels.keys.where((id) => !alive.contains(id)).toList()) {
      _labels.remove(id)!.dispose();
    }
    for (final gain in controller.gains) {
      var label = _labels[gain.id];
      // Keep the shimmer at vsync, but layout the growing digits at 15 Hz.
      // Two held notes must not cause four paragraph layouts every frame.
      final tick = (gain.age * 15).floor();
      if (label == null ||
          (label.points != gain.points &&
              (!gain.holding || tick != label.tick))) {
        label?.dispose();
        label = _labels[gain.id] = _GoldLabel(gain.points, tick);
      }
      final flight = gain.flight;
      final raw = gain.position(target);
      final point = Offset(
        raw.dx.clamp(
          label.fill.width / 2 + 8,
          size.width - label.fill.width / 2 - 8,
        ),
        max(20, raw.dy),
      );
      final pop = gain.age < 0.22
          ? 0.7 + 0.3 * Curves.easeOutBack.transform(gain.age / 0.22)
          : 1.0 + 0.04 * sin((gain.age - 0.22) * 7) * (gain.holding ? 1 : 0);
      final scale = pop * (1 - flight * 0.4);
      final alpha = ((1 - flight) / 0.15).clamp(0.0, 1.0);
      if (flight > 0.75) {
        final pulse = sin((flight - 0.75) / 0.25 * pi);
        canvas.drawCircle(
          target,
          12 + pulse * 16,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFFFD45C).withValues(alpha: pulse * 0.5),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: target, radius: 30)),
        );
      }
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.scale(scale);
      final origin = Offset(-label.fill.width / 2, -label.fill.height / 2);
      final rect = origin & label.fill.size;
      final fading = alpha < 0.999;
      if (fading) {
        canvas.saveLayer(
          rect.inflate(20),
          Paint()..color = Colors.white.withValues(alpha: alpha),
        );
      }
      label.edge.paint(canvas, origin);
      label.fill.paint(canvas, origin);
      for (var i = 0; i < 3; i++) {
        final angle = gain.age * 2 + i * pi * 2 / 3;
        final spark = Offset(
          cos(angle) * (label.fill.width / 2 + 7),
          sin(angle) * 19,
        );
        final radius = (1.5 + 1.5 * sin(gain.age * 8 + i).abs()) * alpha;
        final paint = Paint()
          ..color = const Color(0xFFFFF3B8).withValues(alpha: alpha * 0.85)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          spark - Offset(radius, 0),
          spark + Offset(radius, 0),
          paint,
        );
        canvas.drawLine(
          spark - Offset(0, radius),
          spark + Offset(0, radius),
          paint,
        );
      }
      if (fading) canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _GoldPainter oldDelegate) => true;

  void disposeLabels() {
    for (final label in _labels.values) {
      label.dispose();
    }
  }
}
