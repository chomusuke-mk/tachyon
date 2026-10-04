import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart' show CrossfadeCurve;

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

  DateTime? _lastTickTime;
  Duration _accumulatedTime = Duration.zero;
  void Function()? _onCrossEnd;

  CrossfadeManager({
    this.tickerInterval = const Duration(milliseconds: 25),
  });

  /// Whether a crossfade operation is currently active.
  bool get isActive => _isActive;

  /// Whether the crossfade operation is currently paused.
  bool get isPaused => _isPaused;

  /// The effective duration of the active crossfade.
  Duration get effectiveDuration => _effectiveDuration;

  /// Current progress in range [0.0, 1.0].
  double get progress {
    if (!_isActive || _effectiveDuration.inMilliseconds <= 0) return 0.0;
    return (_accumulatedTime.inMilliseconds / _effectiveDuration.inMilliseconds)
        .clamp(0.0, 1.0);
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
      if (!playerIn.isPlaying) {
        await playerIn.play();
      }
    } catch (e) {
      debugPrint('[CrossfadeManager] Error initializing crossfade: $e');
    }

    if (_operationId != opId) {
      // Operation was superseded during async setup
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

  /// Pauses the active crossfade ticker and players.
  Future<void> pause() async {
    if (!_isActive || _isPaused) return;

    if (_lastTickTime != null) {
      _accumulatedTime += DateTime.now().difference(_lastTickTime!);
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
    if (!_isActive || _isPaused || _operationId != opId || _lastTickTime == null) {
      return;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastTickTime!);
    _lastTickTime = now;
    _accumulatedTime += elapsed;

    final totalMs = _effectiveDuration.inMilliseconds;
    final p = totalMs > 0
        ? (_accumulatedTime.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;

    final vOut = _calculateFadeOut(p, _masterVolume);
    final vIn = _calculateFadeIn(p, _masterVolume);

    _playerOut?.setVolume(vOut);
    _playerIn?.setVolume(vIn);

    if (p >= 1.0) {
      _complete(opId);
    }
  }

  Future<void> _complete(int opId) async {
    if (_operationId != opId) return;

    _timer?.cancel();
    _timer = null;
    _lastTickTime = null;

    final out = _playerOut;
    final inP = _playerIn;
    final vol = _masterVolume;
    final callback = _onCrossEnd;

    _playerOut = null;
    _playerIn = null;
    _onCrossEnd = null;

    try {
      if (out != null) {
        await out.setVolume(0.0);
        await out.stop();
      }
    } catch (_) {}

    try {
      if (inP != null) {
        await inP.setVolume(vol);
      }
    } catch (_) {}

    if (_operationId == opId) {
      _isActive = false;
      _isPaused = false;
      callback?.call();
    } else {
      _isActive = false;
      _isPaused = false;
    }
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
      if (!playerIn.isPlaying) {
        await playerIn.play();
      }
    } catch (_) {}

    if (_operationId == opId) {
      _isActive = false;
      _onCrossEnd?.call();
      _onCrossEnd = null;
    } else {
      _isActive = false;
    }
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
