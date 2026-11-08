/// A monotonic song clock with gradual drift correction. Platform position
/// samples may be quantized, delayed or arrive out of order; none may teleport
/// the tiles backwards. [now] is a monotonic, pause-independent stopwatch.
class PlaybackClock {
  PlaybackClock({required this.now});

  final double Function() now;
  double _position = 0;
  double _lastNow = 0;
  double _correction = 0;
  bool _running = false;

  double get position {
    _advance();
    return _position;
  }

  void reset(double position) {
    _position = position;
    _lastNow = now();
    _correction = 0;
    _running = false;
  }

  void resume() {
    if (_running) return;
    _lastNow = now();
    _running = true;
  }

  void pause() {
    _advance();
    _running = false;
  }

  void synchronize(double audioPosition) {
    if (!_running || !audioPosition.isFinite) return;
    _advance();
    final difference = audioPosition - _position;
    // Ignore millisecond quantization; ease actual drift at at most 10%.
    _correction = difference.abs() <= 0.015 ? 0 : difference;
  }

  void _advance() {
    final current = now();
    final elapsed = (current - _lastNow).clamp(0.0, double.infinity);
    _lastNow = current;
    if (!_running) return;
    final adjustment = _correction.clamp(-elapsed * 0.1, elapsed * 0.1);
    _position += elapsed + adjustment;
    _correction -= adjustment;
  }
}
