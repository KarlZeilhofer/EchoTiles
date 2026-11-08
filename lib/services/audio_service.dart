import 'package:audioplayers/audioplayers.dart';

import 'storage_service.dart';

class AudioService {
  static final AudioService instance = AudioService._internal();

  AudioService._internal();

  final AudioPlayer _musicPlayer = AudioPlayer();
  Duration? _currentDuration;
  Future<void> _pending = Future<void>.value();

  // Serialize source changes with pause/stop so leaving a screen while a file
  // loads cannot start old audio after the next screen has already stopped it.
  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  Duration? get currentDuration => _currentDuration;
  Stream<Duration> get onDurationChanged => _musicPlayer.onDurationChanged;
  Stream<Duration> get onPositionChanged => _musicPlayer.onPositionChanged;
  Stream<void> get onPlayerComplete => _musicPlayer.onPlayerComplete;

  Future<void> init() async {
    // Poll native audio time independently of vsync. A frame-by-frame platform
    // round trip competes with animation and touch handling on slower phones.
    _musicPlayer.positionUpdater = TimerPositionUpdater(
      getPosition: _musicPlayer.getCurrentPosition,
      interval: const Duration(milliseconds: 100),
    );
    await _musicPlayer.setReleaseMode(ReleaseMode.stop);
    await _musicPlayer.setVolume(StorageService.getSoundEnabled() ? 1.0 : 0.0);
    await _musicPlayer.setPlaybackRate(1.0);
    _musicPlayer.onDurationChanged.listen((d) {
      _currentDuration = d;
    });
  }

  Future<Duration?> getDuration() async {
    try {
      _currentDuration = await _musicPlayer.getDuration();
    } catch (_) {}
    return _currentDuration;
  }

  Future<Duration?> getCurrentPosition() async {
    try {
      return await _musicPlayer.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  static Future<Duration?> getAudioDuration(String audioPath) async {
    final player = AudioPlayer();
    try {
      if (audioPath.startsWith('assets/')) {
        await player.setSource(AssetSource(audioPath.substring(7)));
      } else if (audioPath.startsWith('content://') ||
          audioPath.startsWith('http://') ||
          audioPath.startsWith('https://')) {
        await player.setSource(UrlSource(audioPath));
      } else {
        await player.setSource(DeviceFileSource(audioPath));
      }
      final duration = await player.getDuration();
      await player.dispose();
      return duration;
    } catch (_) {
      await player.dispose();
      return null;
    }
  }

  Future<void> playSong(String audioPath) => _enqueue(() async {
    await _musicPlayer.stop();
    await _musicPlayer.setVolume(StorageService.getSoundEnabled() ? 1.0 : 0.0);
    await _musicPlayer.setPlaybackRate(1.0);
    if (audioPath.startsWith('assets/')) {
      await _musicPlayer.play(AssetSource(audioPath.substring(7)));
    } else if (audioPath.startsWith('content://') ||
        audioPath.startsWith('http://') ||
        audioPath.startsWith('https://')) {
      await _musicPlayer.play(UrlSource(audioPath));
    } else {
      await _musicPlayer.play(DeviceFileSource(audioPath));
    }
    _currentDuration = await _musicPlayer.getDuration();
  });

  Future<void> pauseSong() => _enqueue(() async {
    await _musicPlayer.pause();
  });

  Future<void> resumeSong() => _enqueue(() async {
    await _musicPlayer.resume();
  });

  Future<void> stopSong() => _enqueue(() async {
    await _musicPlayer.stop();
  });

  Future<void> dispose() async {
    await _musicPlayer.dispose();
  }
}
