import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

import 'audio_player_adapter.dart';

/// Pure crossfade orchestration manager for transitions between two audio players.
///
/// Encapsulates:
/// - Autonomous 25ms ticker for smooth volume envelope interpolation.
/// - Atomic operation token (`_operationId`) ensuring cancellation is instantaneous and leak-free.
/// - Dynamic real-time master volume scaling with zero jumps.
/// - Deterministic lifecycle with `seek(Duration.zero)` guarantee on incoming player.
/// - Pure effect engine: `cancel()` simply terminates the transition ticker immediately.
class CrossfadeManager {
  final Duration tickerInterval;

  Timer? _timer;
  int _operationId = 0;
  bool _isActive = false;
  bool _isPaused = false;

  AudioPlayerAdapter? _playerOut;
  AudioPlayerAdapter? _playerIn;
  CrossfadeCurve _curve = CrossfadeCurve.equalPower;
  double _masterVolume = 100.0;
  Duration _effectiveDuration = Duration.zero;
  double _playbackRate = 1.0;
  Duration? _startPositionOut;

  DateTime? _lastTickTime;
  Duration _accumulatedTime = Duration.zero;
  void Function()? _onCrossEnd;

  CrossfadeManager({this.tickerInterval = const Duration(milliseconds: 25)});

  /// Whether a crossfade operation is currently active.
  bool get isActive => _isActive;

  /// Whether the crossfade operation is currently paused.
  bool get isPaused => _isPaused;

  /// The effective duration of the active crossfade.
  Duration get effectiveDuration => _effectiveDuration;

  /// The active playback rate used to scale the crossfade media time.
  double get playbackRate => _playbackRate;

  /// Current progress in range [0.0, 1.0].
  double get progress {
    if (!_isActive || _effectiveDuration.inMilliseconds <= 0) return 0.0;
    final pTime =
        (_accumulatedTime.inMilliseconds / _effectiveDuration.inMilliseconds)
            .clamp(0.0, 1.0);
    var pPos = 0.0;
    final out = _playerOut;
    if (out != null && _startPositionOut != null) {
      final currentPos = out.position;
      if (currentPos >= _startPositionOut!) {
        pPos =
            ((currentPos - _startPositionOut!).inMilliseconds /
                    _effectiveDuration.inMilliseconds)
                .clamp(0.0, 1.0);
      }
    }
    return math.max(pTime, pPos);
  }

  /// Begins a crossfade transition from [playerOut] to [playerIn].
  ///
  /// Any active crossfade is immediately and cleanly canceled before starting.
  /// Guarantees:
  /// 1. [playerIn] is seeked to [Duration.zero] before playback starts.
  /// 2. [playerOut] fades out to 0.0, then stops.
  /// 3. [playerIn] fades in to [masterVolume].
  /// 4. [onCrossEnd] is invoked once the transition reaches 100%.
  Future<void> cross({
    required AudioPlayerAdapter playerOut,
    required AudioPlayerAdapter playerIn,
    required Duration targetDuration,
    required CrossfadeCurve curve,
    required double masterVolume,
    double playbackRate = 1.0,
    void Function()? onCrossEnd,
  }) async {
    // 1. Cancel previous operation atomically
    cancel();

    final opId = ++_operationId;
    _playerOut = playerOut;
    _playerIn = playerIn;
    _curve = curve;
    _masterVolume = masterVolume;
    _effectiveDuration = targetDuration;
    _playbackRate = playbackRate > 0 ? playbackRate : 1.0;
    _startPositionOut = playerOut.position;
    _onCrossEnd = onCrossEnd;
    _accumulatedTime = Duration.zero;
    _isPaused = false;

    // Direct transition for zero or sub-threshold durations (<= 100ms)
    if (targetDuration <= const Duration(milliseconds: 100)) {
      await _executeDirectCut(playerOut, playerIn, masterVolume, opId);
      return;
    }

    _isActive = true;

    // 2. Setup initial volumes
    final initialVOut = _calculateFadeOut(0.0, masterVolume);
    final initialVIn = _calculateFadeIn(0.0, masterVolume);

    try {
      await playerOut.setVolume(initialVOut);
      await playerIn.setVolume(initialVIn);
      await playerIn.seek(Duration.zero);
      if (_operationId == opId && !_isPaused && !playerIn.isPlaying) {
        await playerIn.play();
      }
    } catch (e) {
      debugPrint('[CrossfadeManager] Error initializing crossfade: $e');
    }

    if (_operationId != opId) {
      // Operation was superseded during async setup
      return;
    }

    if (_isPaused) {
      // Paused during setup: keep both players silent/paused; resume() will
      // start the ticker.
      try {
        await playerIn.pause();
      } catch (_) {}
      return;
    }

    // 3. Start ticker
    _lastTickTime = DateTime.now();
    _timer = Timer.periodic(tickerInterval, (_) => _onTick(opId));
  }

  /// Updates master volume reference during active crossfade without audio jumps.
  void setMasterVolume(double masterVolume) {
    _masterVolume = masterVolume;
    if (!_isActive || _isPaused) return;

    final p = progress;
    final vOut = _calculateFadeOut(p, _masterVolume);
    final vIn = _calculateFadeIn(p, _masterVolume);

    _playerOut?.setVolume(vOut);
    _playerIn?.setVolume(vIn);
  }

  /// Updates the playback rate during an active crossfade without volume discontinuities.
  void setPlaybackRate(double rate) {
    if (rate > 0) {
      _playbackRate = rate;
    }
  }

  /// Pauses the active crossfade ticker and players.
  Future<void> pause() async {
    if (!_isActive || _isPaused) return;

    if (_lastTickTime != null) {
      final elapsed = DateTime.now().difference(_lastTickTime!);
      final elapsedMediaMicros = (elapsed.inMicroseconds * _playbackRate)
          .round();
      _accumulatedTime += Duration(microseconds: elapsedMediaMicros);
      _lastTickTime = null;
    }
    _timer?.cancel();
    _timer = null;
    _isPaused = true;

    try {
      await _playerOut?.pause();
      await _playerIn?.pause();
    } catch (_) {}
  }

  /// Resumes the paused crossfade ticker and players.
  Future<void> resume() async {
    if (!_isActive || !_isPaused) return;

    _isPaused = false;
    final opId = _operationId;

    try {
      await _playerOut?.play();
      await _playerIn?.play();
    } catch (_) {}

    if (_operationId != opId) return;

    _lastTickTime = DateTime.now();
    _timer = Timer.periodic(tickerInterval, (_) => _onTick(opId));
  }

  /// Cancels the running crossfade transition ticker immediately.
  ///
  /// Guarantees:
  /// - Ticker is stopped synchronously.
  /// - Generation token is invalidated.
  /// - `onCrossEnd` is NOT invoked.
  void cancel() {
    ++_operationId;
    _timer?.cancel();
    _timer = null;
    _isActive = false;
    _isPaused = false;
    _lastTickTime = null;
    _accumulatedTime = Duration.zero;
    _playbackRate = 1.0;
    _startPositionOut = null;

    _playerOut = null;
    _playerIn = null;
    _onCrossEnd = null;
  }

  /// Disposes the manager and releases all resources.
  void dispose() {
    cancel();
  }

  // --------------------------------------------------------------------------
  // Private Helpers & Ticker Logic
  // --------------------------------------------------------------------------

  void _onTick(int opId) {
    if (!_isActive ||
        _isPaused ||
        _operationId != opId ||
        _lastTickTime == null) {
      return;
    }

    final out = _playerOut;
    if (out != null &&
        (out.isCompleted ||
            (out.duration > Duration.zero && out.position >= out.duration))) {
      _complete(opId);
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastTickTime!);
    _lastTickTime = now;
    final elapsedMediaMicros = (elapsed.inMicroseconds * _playbackRate).round();
    _accumulatedTime += Duration(microseconds: elapsedMediaMicros);

    final totalMs = _effectiveDuration.inMilliseconds;
    final pTime = totalMs > 0
        ? (_accumulatedTime.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;

    var pPos = 0.0;
    if (out != null && _startPositionOut != null && totalMs > 0) {
      final currentPos = out.position;
      if (currentPos >= _startPositionOut!) {
        pPos = ((currentPos - _startPositionOut!).inMilliseconds / totalMs)
            .clamp(0.0, 1.0);
      }
    }

    final p = math.max(pTime, pPos);

    final vOut = _calculateFadeOut(p, _masterVolume);
    final vIn = _calculateFadeIn(p, _masterVolume);

    _playerOut?.setVolume(vOut);
    _playerIn?.setVolume(vIn);

    if (p >= 1.0) {
      _complete(opId);
    }
  }

  /// Finalizes the transition atomically.
  ///
  /// The final player commands are *issued* synchronously and in order
  /// (each player processes its commands FIFO), and [_onCrossEnd] is invoked
  /// in the same synchronous turn. This removes the "completing" window in
  /// which a concurrent `pause()`, `cancel()` or `cross()` could observe a
  /// half-finished transition (e.g. `isActive == true` with null players).
  void _complete(int opId) {
    if (_operationId != opId) return;

    _timer?.cancel();
    _timer = null;
    _lastTickTime = null;
    _accumulatedTime = Duration.zero;
    _playbackRate = 1.0;
    _startPositionOut = null;

    final out = _playerOut;
    final inP = _playerIn;
    final callback = _onCrossEnd;

    _playerOut = null;
    _playerIn = null;
    _onCrossEnd = null;
    _isActive = false;
    _isPaused = false;

    if (out != null) {
      unawaited(out.setVolume(0.0).catchError((_) {}));
      unawaited(out.stop().catchError((_) {}));
    }
    if (inP != null) {
      unawaited(inP.setVolume(_masterVolume).catchError((_) {}));
    }

    callback?.call();
  }

  Future<void> _executeDirectCut(
    AudioPlayerAdapter playerOut,
    AudioPlayerAdapter playerIn,
    double masterVolume,
    int opId,
  ) async {
    _isActive = true;
    try {
      await playerOut.setVolume(0.0);
      await playerOut.stop();
      await playerIn.setVolume(masterVolume);
      await playerIn.seek(Duration.zero);
      if (_operationId == opId && !playerIn.isPlaying) {
        await playerIn.play();
      }
    } catch (_) {}

    // Only the operation that still owns the manager may touch its state;
    // a newer cross() may already be running.
    if (_operationId != opId) return;

    final callback = _onCrossEnd;
    _onCrossEnd = null;
    _playerOut = null;
    _playerIn = null;
    _isActive = false;
    _isPaused = false;
    _playbackRate = 1.0;
    _startPositionOut = null;
    callback?.call();
  }

  double _calculateFadeOut(double p, double masterVolume) {
    final progress = p.clamp(0.0, 1.0);
    switch (_curve) {
      case CrossfadeCurve.equalPower:
        return masterVolume * math.cos(math.pi * 0.5 * progress);
      case CrossfadeCurve.linear:
        return masterVolume * (1.0 - progress);
    }
  }

  double _calculateFadeIn(double p, double masterVolume) {
    final progress = p.clamp(0.0, 1.0);
    switch (_curve) {
      case CrossfadeCurve.equalPower:
        return masterVolume * math.sin(math.pi * 0.5 * progress);
      case CrossfadeCurve.linear:
        return masterVolume * progress;
    }
  }
}
