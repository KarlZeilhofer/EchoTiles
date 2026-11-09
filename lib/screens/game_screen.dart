import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../l10n/app_localizations.dart';
import '../models/app_theme.dart';
import '../models/game_models.dart';
import '../models/song_analysis.dart';
import '../models/rhythm_timeline.dart';
import '../models/playback_clock.dart';
import '../models/tile_hit_test.dart';
import '../services/audio_service.dart';
import '../services/haptics.dart';
import '../services/storage_service.dart';

class GameScreen extends StatefulWidget {
  final SongItem song;
  final SongAnalysis analysis;
  final AppThemeData appTheme;

  const GameScreen({
    super.key,
    required this.song,
    required this.analysis,
    required this.appTheme,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _targetLineFactor = RhythmTimeline.targetLineFactor;
  static const double _tileHeightFactor = TileHitTest.tileHeightFactor;
  late Ticker _ticker;
  final Stopwatch _monotonic = Stopwatch();
  late final PlaybackClock _clock;
  final ValueNotifier<int> _frames = ValueNotifier<int>(0);
  int _lastHudTick = -1;
  bool _audioStarted = false;
  bool _audioStarting = false;
  int _generation = 0;
  GameStatus _status = GameStatus.ready;
  final List<GameTile> _tiles = [];
  final List<HitFeedback> _feedbacks = [];
  final Map<int, int> _activeHolds = {};
  int _score = 0;
  int _combo = 0;
  int _maxCombo = 0;
  int _nextTileIndex = 0;
  int _failedLane = -1;
  double _songProgress = 0.0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _completeSub;

  double get _monotonicTime => _monotonic.elapsedMicroseconds / 1000000;
  double get _time => _clock.position;

  @override
  void initState() {
    super.initState();
    _monotonic.start();
    _clock = PlaybackClock(now: () => _monotonicTime);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _initLevel();
    _positionSub = AudioService.instance.onPositionChanged.listen((pos) {
      if (!_audioStarted || _audioStarting || _status != GameStatus.playing) {
        return;
      }
      _clock.synchronize(pos.inMicroseconds / 1000000);
    });
    _completeSub = AudioService.instance.onPlayerComplete.listen((_) {
      if (mounted && _status == GameStatus.playing) {
        // Keep the judgment window open for a note right at the end.
        _clock.synchronize(widget.analysis.duration);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _status == GameStatus.playing) {
      _pauseGame();
    }
  }

  void _initLevel() {
    _generation++;
    if (_ticker.isActive) _ticker.stop();
    _clock.reset(0);
    _lastHudTick = -1;
    _audioStarted = false;
    _audioStarting = false;
    _status = GameStatus.ready;
    _score = 0;
    _combo = 0;
    _maxCombo = 0;
    _nextTileIndex = 1;
    _failedLane = -1;
    _songProgress = 0;
    _tiles.clear();
    _feedbacks.clear();
    _activeHolds.clear();
    final first = widget.analysis.notes.first;
    final endY = RhythmTimeline.position(
      first.endTime,
      0,
      widget.analysis.duration,
      variant: widget.analysis.variant,
    );
    _tiles.add(
      GameTile(
        id: 0,
        lane: first.lane,
        y: _targetLineFactor,
        noteIndex: 0,
        isLong: first.isLong,
        endY: endY,
        length: first.isLong
            ? max(1.0, (_targetLineFactor - endY) / _tileHeightFactor)
            : 1,
      ),
    );
    AudioService.instance.stopSong();
  }

  Future<void> _beginAudio() async {
    final generation = _generation;
    _audioStarting = true;
    _audioStarted = true;
    _clock.reset(0);
    try {
      await AudioService.instance.playSong(widget.song.assetAudio);
      final position = await AudioService.instance.getCurrentPosition();
      if (!mounted || generation != _generation) return;
      _clock.reset((position?.inMicroseconds ?? 0) / 1000000);
      _audioStarting = false;
      if (_status == GameStatus.playing) {
        _clock.resume();
      } else {
        await AudioService.instance.pauseSong();
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        _triggerGameOver(-1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).analysisFailed)),
        );
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (_status != GameStatus.playing) return;
    final time = _time;
    final analysis = widget.analysis;
    _songProgress = (time / analysis.duration).clamp(0.0, 1.0);
    while (_nextTileIndex < analysis.notes.length) {
      final note = analysis.notes[_nextTileIndex];
      final y = RhythmTimeline.position(
        note.time,
        time,
        analysis.duration,
        variant: analysis.variant,
      );
      if (y < -0.25) break;
      _tiles.add(
        GameTile(
          id: _nextTileIndex,
          lane: note.lane,
          y: y,
          noteIndex: _nextTileIndex,
          isLong: note.isLong,
        ),
      );
      _nextTileIndex++;
    }
    for (final tile in _tiles) {
      final note = analysis.notes[tile.noteIndex];
      tile.y = tile.id == 0 && tile.isHolding && time < note.time
          ? _targetLineFactor
          : RhythmTimeline.position(
              note.time,
              time,
              analysis.duration,
              variant: analysis.variant,
            );
      tile.endY = RhythmTimeline.position(
        note.endTime,
        time,
        analysis.duration,
        variant: analysis.variant,
      );
      if (tile.isLong) {
        tile.length = max(1.0, (tile.y - tile.endY) / _tileHeightFactor);
      }
      if (tile.isHolding) {
        _advanceHold(tile, time);
        // Keep the pointer attached until release, including on the last note.
        // Holding beyond the tail is a miss, rather than an automatic success.
        if (note.isReleaseLate(time)) {
          _triggerGameOver(tile.lane);
          return;
        }
      }
      if (TileHitTest.isMissed(tile)) {
        tile.isMissed = true;
        _triggerGameOver(tile.lane);
        return;
      }
    }
    _tiles.removeWhere((t) => t.isHit && !t.isHolding && t.y > 1.3);
    final now = DateTime.now().millisecondsSinceEpoch;
    _feedbacks.removeWhere((f) => now - f.timestamp > 700);
    if (time >= analysis.duration &&
        _nextTileIndex == analysis.notes.length &&
        _tiles.every((t) => t.isHit && !t.isHolding)) {
      _triggerVictory();
      return;
    }
    // Tiles repaint at vsync; score/progress widgets update at 10 Hz.
    _frames.value++;
    final hudTick = (time * 10).floor();
    if (hudTick != _lastHudTick) {
      _lastHudTick = hudTick;
      setState(() {});
    }
  }

  void _startGame() {
    _status = GameStatus.playing;
    _clock.reset(0);
    _beginAudio();
    _ticker.start();
  }

  void _pauseGame() {
    if (_status != GameStatus.playing) return;
    _clock.pause();
    _ticker.stop();
    setState(() => _status = GameStatus.paused);
    if (_audioStarted) AudioService.instance.pauseSong();
  }

  void _resumeGame() async {
    if (_status != GameStatus.paused) return;
    if (_audioStarted && !_audioStarting) {
      await AudioService.instance.resumeSong();
    }
    if (!mounted || _status != GameStatus.paused) return;
    setState(() => _status = GameStatus.playing);
    if (!_audioStarting) _clock.resume();
    _ticker.start();
  }

  void _triggerGameOver(int lane, [Offset? mistapOffset]) {
    _status = GameStatus.gameOver;
    _failedLane = lane;
    _clock.pause();
    _ticker.stop();
    AudioService.instance.stopSong();
    Haptics.heavy();
    if (mistapOffset != null) {
      _feedbacks.add(
        HitFeedback(
          quality: HitQuality.miss,
          x: mistapOffset.dx,
          y: mistapOffset.dy,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    StorageService.setHighScore(widget.song.id, _score);
    StorageService.setBestCombo(_maxCombo);
    setState(() {});
  }

  void _triggerVictory() {
    _status = GameStatus.victory;
    _clock.pause();
    _ticker.stop();
    AudioService.instance.stopSong();
    Haptics.medium();
    StorageService.setHighScore(widget.song.id, _score);
    StorageService.setStars(widget.song.id, _calculateStars());
    StorageService.setBestCombo(_maxCombo);
    setState(() {});
  }

  int _calculateStars() {
    if (_songProgress >= 0.95) return 3;
    if (_songProgress >= 0.65) return 2;
    if (_songProgress >= 0.35) return 1;
    return 0;
  }

  void _onPointerDown(PointerDownEvent event, Size screenSize) {
    if (_status != GameStatus.playing && _status != GameStatus.ready) return;
    if (event.localPosition.dy < 75) return;
    if (_status == GameStatus.playing &&
        _activeHolds.length >= SongAnalysis.maxSimultaneousTiles) {
      return;
    }
    final laneWidth = screenSize.width / 4;
    final tapX = event.localPosition.dx;
    final tapY = event.localPosition.dy;
    final lane = (tapX / laneWidth).floor().clamp(0, 3);
    // Use the positions currently painted, exactly as the original game does.
    final tile = TileHitTest.select(
      _tiles,
      lane,
      tapY / screenSize.height,
      _targetLineFactor,
    );
    final isStartTap = _status == GameStatus.ready;
    if (tile == null) {
      // During source preparation keep valid visible taps, but don't punish a
      // second touch while the first cleared tile is waiting for audio startup.
      if (_audioStarting && !isStartTap) return;
      _triggerGameOver(lane, Offset(tapX, tapY));
      return;
    }
    if (isStartTap) {
      if (tile.id != 0) {
        _triggerGameOver(lane, Offset(tapX, tapY));
        return;
      }
      _startGame();
      // Continue through normal hit/hold handling: START is the first real
      // note, not a disposable duplicate that needs another tap later.
    }
    final quality = TileHitTest.quality(tile, _targetLineFactor);
    _combo++;
    _maxCombo = max(_maxCombo, _combo);
    _score +=
        (quality == HitQuality.perfect
            ? 100
            : quality == HitQuality.great
            ? 80
            : 50) +
        _combo * 2;
    if (tile.isLong) {
      tile.isHolding = true;
      final note = widget.analysis.notes[tile.noteIndex];
      tile.holdScoredUntil = _time.clamp(note.time, note.endTime);
      tile.holdProgress = ((tile.holdScoredUntil - note.time) / note.duration)
          .clamp(0.0, 1.0);
      _activeHolds[event.pointer] = tile.id;
    } else {
      tile.isHit = true;
    }
    Haptics.light();
    _feedbacks.add(
      HitFeedback(
        quality: quality,
        x: tapX,
        y: tapY,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    setState(() {});
  }

  void _advanceHold(GameTile tile, double time) {
    final note = widget.analysis.notes[tile.noteIndex];
    final heldUntil = time.clamp(note.time, note.endTime);
    final heldSeconds = max(0.0, heldUntil - tile.holdScoredUntil);
    tile.holdScoredUntil = heldUntil;
    // Original live rewards, capped at the musical end. The completion bonus
    // is awarded separately, only after the player actually releases.
    final points = tile.holdScoreRemainder + heldSeconds * 220;
    final earned = (points + 1e-9).floor();
    _score += earned;
    tile.holdScoreRemainder = points - earned;
    final previousStep = (tile.holdProgress * 10).floor();
    tile.holdProgress = time >= note.endTime
        ? 1.0
        : ((time - note.time) / note.duration).clamp(0.0, 1.0);
    final steps = (tile.holdProgress * 10).floor() - previousStep;
    if (steps > 0) {
      _combo += steps;
      _maxCombo = max(_maxCombo, _combo);
      Haptics.light();
    }
  }

  void _finishHold(GameTile tile) {
    tile.isHolding = false;
    tile.isHit = true;
    tile.holdProgress = 1;
    _activeHolds.removeWhere((_, id) => id == tile.id);
    _score += 150;
    _combo += 2;
    _maxCombo = max(_maxCombo, _combo);
    Haptics.medium();
  }

  void _onPointerMove(PointerMoveEvent event, Size screenSize) {
    final id = _activeHolds[event.pointer];
    if (id == null) return;
    final tile = _tiles.where((t) => t.id == id && t.isHolding).firstOrNull;
    if (tile == null) return;
    final lane = (event.localPosition.dx / (screenSize.width / 4))
        .floor()
        .clamp(0, 3);
    if (lane != tile.lane) {
      _activeHolds.remove(event.pointer);
      _releaseHold(tile, cancelled: true);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final id = _activeHolds.remove(event.pointer);
    if (id == null) return;
    final tile = _tiles.where((t) => t.id == id && t.isHolding).firstOrNull;
    if (tile == null) return;
    _releaseHold(tile);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final id = _activeHolds.remove(event.pointer);
    if (id == null) return;
    final tile = _tiles.where((t) => t.id == id && t.isHolding).firstOrNull;
    if (tile != null) _releaseHold(tile, cancelled: true);
  }

  void _releaseHold(GameTile tile, {bool cancelled = false}) {
    if (_status != GameStatus.playing && _status != GameStatus.paused) return;
    final time = _time;
    final note = widget.analysis.notes[tile.noteIndex];
    // Check input too: a late up/move/cancel must not dodge the next frame's
    // deadline when rendering stalls. Paused time stays frozen.
    if (note.isReleaseLate(time)) {
      _triggerGameOver(tile.lane);
      return;
    }
    _advanceHold(tile, time);
    if (!cancelled && time >= note.endTime) {
      _finishHold(tile);
    } else {
      tile.isHolding = false;
      tile.isHit = true;
      if (!cancelled && tile.holdProgress >= 0.85) {
        _score += 100;
        Haptics.medium();
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _clock.pause();
    _ticker.dispose();
    _frames.dispose();
    _monotonic.stop();
    _positionSub?.cancel();
    _completeSub?.cancel();
    AudioService.instance.stopSong();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.appTheme;
    final l10n = AppLocalizations.of(context);
    final qualityLabels = {
      HitQuality.perfect: l10n.qualityPerfect,
      HitQuality.great: l10n.qualityGreat,
      HitQuality.good: l10n.qualityGood,
      HitQuality.miss: l10n.qualityMiss,
    };

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                return Listener(
                  onPointerDown: (e) => _onPointerDown(e, size),
                  onPointerMove: (e) => _onPointerMove(e, size),
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: _GameTilesPainter(
                        repaint: _frames,
                        tiles: _tiles,
                        feedbacks: _feedbacks,
                        appTheme: theme,
                        failedLane: _failedLane,
                        isReady: _status == GameStatus.ready,
                        targetLineFactor: _targetLineFactor,
                        tileHeightFactor: _tileHeightFactor,
                        startLabel: l10n.start,
                        qualityLabels: qualityLabels,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader(theme)),
          if (_status == GameStatus.ready)
            Positioned(
              left: 24,
              right: 24,
              top: 150,
              child: IgnorePointer(
                child: Text(
                  AppLocalizations.of(context).startRhythm,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.textPrimary, fontSize: 16),
                ),
              ),
            ),
          if (_status == GameStatus.paused) _buildPauseOverlay(theme),
          if (_status == GameStatus.gameOver)
            _buildEndOverlay(theme, isWin: false),
          if (_status == GameStatus.victory)
            _buildEndOverlay(theme, isWin: true),
        ],
      ),
    );
  }

  Widget _buildHeader(AppThemeData theme) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.border.withValues(alpha: 0.4),
              width: 1.8,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: theme.textPrimary,
                        size: 22,
                      ),
                      onPressed: () {
                        Haptics.select();
                        Navigator.of(context).pop();
                      },
                    ),
                    Column(
                      children: [
                        Text(
                          '$_score',
                          key: const ValueKey('game-score'),
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: theme.textPrimary,
                          ),
                        ),
                        if (_combo > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.playBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              AppLocalizations.of(context).comboLabel(_combo),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        _status == GameStatus.paused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        color: theme.textPrimary,
                        size: 28,
                      ),
                      onPressed: () {
                        Haptics.select();
                        if (_status == GameStatus.playing ||
                            _status == GameStatus.ready) {
                          _pauseGame();
                        } else if (_status == GameStatus.paused) {
                          _resumeGame();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _songProgress,
                    minHeight: 6,
                    backgroundColor: theme.surfaceVariant.withValues(
                      alpha: 0.6,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(theme.playBg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPauseOverlay(AppThemeData theme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.dialogBg,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).paused,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Haptics.select();
                  _resumeGame();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.playBg,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).resume,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: theme.border, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).home,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEndOverlay(AppThemeData theme, {required bool isWin}) {
    final stars = _calculateStars();
    final highScore = StorageService.getHighScore(widget.song.id);

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 28),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: theme.dialogBg,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isWin
                    ? AppLocalizations.of(context).songCompleted
                    : AppLocalizations.of(context).outOfRhythm,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                  color: isWin ? theme.playBg : const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i < stars;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      active ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: active ? const Color(0xFFFFB800) : theme.border,
                      size: 38,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context).score,
                          style: TextStyle(
                            color: theme.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$_score',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context).bestScore,
                          style: TextStyle(
                            color: theme.textMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$highScore',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                onPressed: () {
                  Haptics.select();
                  _initLevel();
                  setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isWin
                      ? theme.playBg
                      : const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  isWin
                      ? AppLocalizations.of(context).playAgain
                      : AppLocalizations.of(context).tryAgain,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: BorderSide(color: theme.border, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).home,
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameTilesPainter extends CustomPainter {
  final List<GameTile> tiles;
  final List<HitFeedback> feedbacks;
  final AppThemeData appTheme;
  final int failedLane;
  final bool isReady;
  final double targetLineFactor;
  final double tileHeightFactor;
  final String startLabel;
  final Map<HitQuality, String> qualityLabels;

  _GameTilesPainter({
    required Listenable repaint,
    required this.tiles,
    required this.feedbacks,
    required this.appTheme,
    required this.failedLane,
    required this.isReady,
    required this.targetLineFactor,
    required this.tileHeightFactor,
    required this.startLabel,
    required this.qualityLabels,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final laneWidth = size.width / 4;

    final laneDividerPaint = Paint()
      ..color = appTheme.border.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;

    for (int i = 1; i < 4; i++) {
      final x = i * laneWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), laneDividerPaint);
    }

    final targetLineY = size.height * targetLineFactor;
    final targetLinePaint = Paint()
      ..color = appTheme.playBg.withValues(alpha: 0.55)
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(0, targetLineY),
      Offset(size.width, targetLineY),
      targetLinePaint,
    );

    if (failedLane >= 0) {
      final failRect = Rect.fromLTWH(
        failedLane * laneWidth,
        0,
        laneWidth,
        size.height,
      );
      final failPaint = Paint()
        ..color = const Color(0xFFEF4444).withValues(alpha: 0.35);
      canvas.drawRect(failRect, failPaint);
    }

    for (final tile in tiles) {
      if (tile.isHit && !tile.isHolding) continue;

      final tileX = tile.lane * laneWidth;
      final tileHeight = size.height * TileHitTest.height(tile);
      final tileY = size.height * TileHitTest.top(tile);

      final rect = Rect.fromLTWH(
        tileX + 2.0,
        tileY,
        laneWidth - 4.0,
        tileHeight,
      );

      if (tile.isLong) {
        final tailPaint = Paint()
          ..color = appTheme.tileTailColor.withValues(alpha: 0.70);
        canvas.drawRect(rect, tailPaint);

        if (tile.isHolding) {
          final progressHeight = tileHeight * tile.holdProgress;
          final filledRect = Rect.fromLTWH(
            tileX + 2.0,
            tileY + tileHeight - progressHeight,
            laneWidth - 4.0,
            progressHeight,
          );
          final hitFillPaint = Paint()
            ..color = appTheme.tileHitColor.withValues(alpha: 0.85);
          canvas.drawRect(filledRect, hitFillPaint);

          final contactY = tileY + tileHeight - progressHeight;
          final sparkPaint = Paint()
            ..color = Colors.white
            ..strokeWidth = 3.0;
          canvas.drawLine(
            Offset(tileX + 3.0, contactY),
            Offset(tileX + laneWidth - 3.0, contactY),
            sparkPaint,
          );
        }

        final borderPaint = Paint()
          ..color = tile.isHolding ? appTheme.tileHitColor : appTheme.tileBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRect(rect, borderPaint);

        final centerX = tileX + laneWidth / 2;
        final circleRadius = min(16.0, (laneWidth - 14) / 2);
        final circleCenter = Offset(
          centerX,
          tileY + tileHeight - circleRadius - 8,
        );
        final lineTop = tileY + 8;
        final lineBottom = circleCenter.dy - circleRadius;

        if (lineBottom > lineTop) {
          final linePaint = Paint()
            ..color = Colors.white.withValues(
              alpha: tile.isHolding ? 0.95 : 0.75,
            )
            ..strokeWidth = 3.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(
            Offset(centerX, lineTop),
            Offset(centerX, lineBottom),
            linePaint,
          );
          canvas.drawCircle(Offset(centerX, lineTop), 3.5, linePaint);
        }

        final circlePaint = Paint()
          ..color = tile.isHolding
              ? appTheme.tileHitColor
              : Colors.white.withValues(alpha: 0.95)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(circleCenter, circleRadius, circlePaint);

        final circleBorder = Paint()
          ..color = tile.isHolding ? Colors.white : appTheme.tileBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(circleCenter, circleRadius, circleBorder);

        final innerDot = Paint()
          ..color = tile.isHolding ? Colors.white : appTheme.tileColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(circleCenter, circleRadius * 0.45, innerDot);
      } else {
        final tilePaint = Paint()..color = appTheme.tileColor;
        canvas.drawRect(rect, tilePaint);

        final borderPaint = Paint()
          ..color = appTheme.tileBorder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRect(rect, borderPaint);
      }

      if (isReady && tile.id == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: startLabel,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              fontFamily: 'Fredoka',
              letterSpacing: 1.5,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            tileX + (laneWidth - tp.width) / 2,
            (tile.isLong
                ? tile.y * size.height -
                      size.height * tileHeightFactor / 2 -
                      tp.height / 2
                : tileY + (tileHeight - tp.height) / 2),
          ),
        );
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final fb in feedbacks) {
      final elapsed = now - fb.timestamp;
      final progress = (elapsed / 700.0).clamp(0.0, 1.0);
      final alpha = (1.0 - progress).clamp(0.0, 1.0);
      final floatOffset = progress * 36.0;

      Color color;
      switch (fb.quality) {
        case HitQuality.perfect:
          color = const Color(0xFFFFB800);
          break;
        case HitQuality.great:
          color = appTheme.playBg;
          break;
        case HitQuality.good:
          color = appTheme.songsBg;
          break;
        default:
          color = const Color(0xFFEF4444);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: qualityLabels[fb.quality] ?? '',
          style: TextStyle(
            color: color.withValues(alpha: alpha),
            fontSize: 20,
            fontWeight: FontWeight.w900,
            fontFamily: 'Fredoka',
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(fb.x - (tp.width / 2), fb.y - floatOffset - (tp.height / 2)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GameTilesPainter oldDelegate) => true;
}
