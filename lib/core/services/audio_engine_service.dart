import 'dart:async';
import 'dart:math' as math;

import 'package:miniaudio_player/miniaudio_player.dart' show AudioDevice, Equalizer;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/playback/domain/behavior_subject.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'audio_player_adapter.dart';
import 'queue_manager.dart';

// ============================================================================
// AUDIO ENGINE SERVICE INTERFACE
// ============================================================================

// ============================================================================
// EXCLUSIVE AUDIO / CROSSFADE CONFLICT EXCEPTION
// ============================================================================

class ExclusiveAudioCrossfadeException implements Exception {
  final String message;
  const ExclusiveAudioCrossfadeException(this.message);

  @override
  String toString() => 'ExclusiveAudioCrossfadeException: $message';
}

// ============================================================================
// AUDIO ENGINE SERVICE IMPLEMENTATION
// ============================================================================

/// Production and testable implementation of [AudioEngineService].
///
/// Coordinates two [AudioPlayerAdapter] instances (Player A and Player B):
/// - Role Swapping: Player A and Player B alternate roles between active and standby.
/// - Active Player plays current song and drives UI progress streams.
/// - When remaining track duration <= effective crossfade duration, standby player
///   preloads and starts the next track at volume 0.0.
/// - 25ms periodic ticker automates the volume curve (Equal-Power or Linear).
/// - On completion, outgoing player stops, roles swap, and the incoming player
///   continues uninterrupted.
/// - Gapless mode: when crossfade duration == 0s, transitions instantly.
/// - Integrates with [QueueManager] for queue, shuffle, loop, and infinite mix.
/// - Implements [AudioSessionPlayerDelegate] for audio focus and session handling.
class AudioEngineService {
  final AudioPlayerAdapter _playerA;
  final AudioPlayerAdapter _playerB;
  late AudioPlayerAdapter _activePlayer;
  late AudioPlayerAdapter _standbyPlayer;

  final QueueManager _queueManager;
  final Duration tickerInterval;

  final BehaviorSubject<PlaybackState> _stateSubject;
  final List<StreamSubscription> _activeSubscriptions = [];

  // Crossfade state
  CrossfadeConfig _crossfadeConfig = const CrossfadeConfig();
  bool _isCrossfading = false;
  bool _isManualCrossfade = false;
  Timer? _fadeTimer;
  DateTime? _fadeTickStartTime;
  Duration _accumulatedFadeDuration = Duration.zero;
  Duration _effectiveCrossfadeDuration = Duration.zero;

  // Effects and audio properties
  double _masterVolume = AppDefaults.volumeDefault;
  double _playbackRate = AppDefaults.playbackRateDefault;
  double _playbackPitch = AppDefaults.playbackPitchDefault;
  bool _skipSilence = false;
  Equalizer _equalizer = Equalizer.flat;
  AudioDevice? _currentDevice;

  AudioEngineService({
    AudioPlayerAdapter? playerA,
    AudioPlayerAdapter? playerB,
    QueueManager? queueManager,
    this.tickerInterval = const Duration(milliseconds: 25),
    math.Random? random,
  }) : _playerA = playerA ?? AudioPlayerAdapter(),
       _playerB = playerB ?? AudioPlayerAdapter(),
       _queueManager = queueManager ?? QueueManager(random: random),
       _stateSubject = BehaviorSubject<PlaybackState>(
         const PlaybackState.initial(),
       ) {
    _activePlayer = _playerA;
    _standbyPlayer = _playerB;
    _bindActivePlayerStreams();
  }

  AudioPlayerAdapter get activePlayer => _activePlayer;
  AudioPlayerAdapter get standbyPlayer => _standbyPlayer;
  QueueManager get queueManager => _queueManager;
  bool get isCrossfading => _isCrossfading;
  CrossfadeConfig get crossfadeConfig => _crossfadeConfig;
  Equalizer get equalizer => _equalizer;
  AudioDevice? get currentDevice => _currentDevice;

  bool get isPlaying => _activePlayer.isPlaying;

  Stream<PlaybackState> get stateStream => _stateSubject;

  PlaybackState get currentState => _stateSubject.value;

  // --------------------------------------------------------------------------
  // Stream Management
  // --------------------------------------------------------------------------

  void _emitState() {
    final newState = currentState.copyWith(
      index: _queueManager.currentIndex >= 0 ? _queueManager.currentIndex : 0,
      playables: _queueManager.activeQueue,
      mixOffset: _queueManager.mixOffset,
      playing: _activePlayer.isPlaying,
      buffering: _activePlayer.isBuffering,
      completed: _activePlayer.isCompleted,
      position: _activePlayer.position,
      duration: _activePlayer.duration,
      volume: _masterVolume,
      rate: _playbackRate,
      pitch: _playbackPitch,
      shuffle: _queueManager.isShuffled,
      loop: _queueManager.loopMode,
      crossfadeConfig: _crossfadeConfig,
      crossfadeDuration: _crossfadeConfig.duration,
      skipSilence: _skipSilence,
    );
    _stateSubject.add(newState);
  }

  void _bindActivePlayerStreams() {
    for (final sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();

    _activeSubscriptions.add(
      _activePlayer.positionStream.listen((pos) {
        _stateSubject.add(currentState.copyWith(position: pos));
        _checkCrossfadeTrigger(pos, _activePlayer.duration);
      }),
    );

    _activeSubscriptions.add(
      _activePlayer.durationStream.listen((dur) {
        _stateSubject.add(currentState.copyWith(duration: dur));
      }),
    );

    _activeSubscriptions.add(
      _activePlayer.playingStream.listen((playing) {
        _stateSubject.add(currentState.copyWith(playing: playing));
      }),
    );

    _activeSubscriptions.add(
      _activePlayer.bufferingStream.listen((buffering) {
        _stateSubject.add(currentState.copyWith(buffering: buffering));
      }),
    );

    _activeSubscriptions.add(
      _activePlayer.completedStream.listen((completed) {
        if (completed) {
          if (_isCrossfading) {
            _completeCrossfade();
          } else {
            _handleTrackCompleted();
          }
        }
      }),
    );
  }

  // --------------------------------------------------------------------------
  // Core Playback Operations
  // --------------------------------------------------------------------------

  Future<void> open(
    List<QueueItem> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    _abortActiveCrossfade();

    if (playables.isEmpty) {
      _queueManager.clear();
      await _activePlayer.stop();
      await _standbyPlayer.stop();
      _emitState();
      return;
    }

    _queueManager.setQueue(playables, startIndex: index, shuffle: shuffle);

    final targetTrack = _queueManager.currentTrack;
    if (targetTrack == null) {
      _emitState();
      return;
    }

    await _activePlayer.setVolume(_masterVolume);
    await _activePlayer.setRate(_playbackRate);
    await _activePlayer.setPitch(_playbackPitch);
    await _activePlayer.setEqualizer(_equalizer);
    await _activePlayer.open(targetTrack.filePath, play: play);

    _emitState();
  }

  Future<void> play() async {
    if (_queueManager.activeQueue.isEmpty) return;
    if (_isCrossfading) {
      await _activePlayer.play();
      await _standbyPlayer.play();
      if (_fadeTimer == null || !_fadeTimer!.isActive) {
        _fadeTickStartTime = DateTime.now();
        _fadeTimer?.cancel();
        _fadeTimer = Timer.periodic(tickerInterval, (_) {
          _onCrossfadeTick();
        });
      }
    } else {
      await _activePlayer.play();
    }
    _emitState();
  }

  Future<void> pause() async {
    if (_isCrossfading) {
      if (_fadeTickStartTime != null) {
        _accumulatedFadeDuration += DateTime.now().difference(
          _fadeTickStartTime!,
        );
        _fadeTickStartTime = null;
      }
      _fadeTimer?.cancel();
      _fadeTimer = null;
      await _activePlayer.pause();
      await _standbyPlayer.pause();
    } else {
      await _activePlayer.pause();
    }
    _emitState();
  }

  Future<void> stop() async {
    _abortActiveCrossfade();
    await _activePlayer.stop();
    await _standbyPlayer.stop();
    _emitState();
  }

  Future<void> seek(Duration position) async {
    if (_queueManager.activeQueue.isEmpty) return;

    if (_isCrossfading) {
      _abortActiveCrossfade();
    }

    await _activePlayer.seek(position);
    _emitState();
  }

  Future<void> next() async {
    if (_queueManager.activeQueue.isEmpty) return;

    // Next during active crossfade fast-forwards immediately
    if (_isCrossfading) {
      await _fastForwardCrossfade();
      return;
    }

    if (_queueManager.loopMode == Loop.one) {
      await _activePlayer.seek(Duration.zero);
      await _activePlayer.play();
      _emitState();
      return;
    }

    final nextItem = await _queueManager.next(isManual: true);
    if (nextItem != null) {
      await _performManualCrossfade(nextItem);
    } else {
      // Loop.off at end of queue
      await _activePlayer.stop();
      _stateSubject.add(currentState.copyWith(completed: true, playing: false));
    }
  }

  Future<void> previous() async {
    if (_queueManager.activeQueue.isEmpty) return;

    if (_isCrossfading) {
      await _fastForwardCrossfade();
    }

    // Standard behavior: if current track played > 3 seconds, restart it
    if (_activePlayer.position > const Duration(seconds: 3)) {
      await _activePlayer.seek(Duration.zero);
      _emitState();
      return;
    }

    final prevItem = _queueManager.previous(position: _activePlayer.position);
    if (prevItem != null) {
      await _performManualCrossfade(prevItem);
    } else {
      await _activePlayer.seek(Duration.zero);
      _emitState();
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queueManager.activeQueue.length) return;

    if (_isCrossfading) {
      await _fastForwardCrossfade();
    }

    final item = _queueManager.jumpTo(index);
    if (item != null) {
      await _performManualCrossfade(item);
    }
  }

  Future<void> _performManualCrossfade(QueueItem targetTrack) async {
    final manualDuration = _crossfadeConfig.manualDuration;
    if (!_crossfadeConfig.enabled ||
        manualDuration == Duration.zero ||
        !_activePlayer.isPlaying) {
      await _activePlayer.open(targetTrack.filePath, play: true);
      _emitState();
      return;
    }

    _isCrossfading = true;
    _isManualCrossfade = true;
    _accumulatedFadeDuration = Duration.zero;
    _fadeTickStartTime = DateTime.now();
    _effectiveCrossfadeDuration = manualDuration;

    await _standbyPlayer.setVolume(0.0);
    await _standbyPlayer.setRate(_playbackRate);
    await _standbyPlayer.setPitch(_playbackPitch);
    await _standbyPlayer.setEqualizer(_equalizer);
    await _standbyPlayer.open(targetTrack.filePath, play: true);

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(tickerInterval, (_) {
      _onCrossfadeTick();
    });

    _emitState();
  }

  // --------------------------------------------------------------------------
  // Crossfade Orchestration Engine
  // --------------------------------------------------------------------------

  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    _crossfadeConfig = config;
    _emitState();
  }

  void _checkCrossfadeTrigger(
    Duration currentPosition,
    Duration totalDuration,
  ) {
    if (_isCrossfading) return;
    if (!_crossfadeConfig.enabled ||
        _crossfadeConfig.duration == Duration.zero) {
      return;
    }
    if (totalDuration <= Duration.zero) return;

    final nextTrack = _getNextTrackForCrossfade();
    if (nextTrack == null) return;

    // Symmetric clamping: clamped by outgoing track duration / 2 AND incoming track duration / 2
    var effectiveCrossfade = _crossfadeConfig.effectiveDuration(totalDuration);
    if (nextTrack.duration > Duration.zero) {
      final nextEffective = _crossfadeConfig.effectiveDuration(
        nextTrack.duration,
      );
      if (nextEffective < effectiveCrossfade) {
        effectiveCrossfade = nextEffective;
      }
    }
    if (effectiveCrossfade <= Duration.zero) return;

    final remaining = totalDuration - currentPosition;
    if (remaining <= Duration.zero) return;

    if (effectiveCrossfade > remaining) {
      effectiveCrossfade = remaining;
    }
    if (effectiveCrossfade <= Duration.zero) return;

    if (remaining <= effectiveCrossfade) {
      _startCrossfade(effectiveCrossfade, nextTrack);
    }
  }

  QueueItem? _getNextTrackForCrossfade() {
    if (_queueManager.activeQueue.isEmpty) return null;

    if (_queueManager.loopMode == Loop.one) {
      return null;
    }
    if (_queueManager.currentIndex < _queueManager.activeQueue.length - 1) {
      return _queueManager.activeQueue[_queueManager.currentIndex + 1];
    }
    if (_queueManager.loopMode == Loop.all) {
      return _queueManager.activeQueue[0];
    }
    return null; // End of queue with Loop.off -> do not crossfade
  }

  Future<void> _startCrossfade(
    Duration effectiveDuration,
    QueueItem nextTrack,
  ) async {
    _isCrossfading = true;
    _isManualCrossfade = false;
    _accumulatedFadeDuration = Duration.zero;
    _fadeTickStartTime = DateTime.now();
    _effectiveCrossfadeDuration = effectiveDuration;

    // Prime standby player
    await _standbyPlayer.setVolume(0.0);
    await _standbyPlayer.setRate(_playbackRate);
    await _standbyPlayer.setPitch(_playbackPitch);
    await _standbyPlayer.setEqualizer(_equalizer);
    await _standbyPlayer.open(nextTrack.filePath, play: true);

    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(tickerInterval, (_) {
      _onCrossfadeTick();
    });
  }

  void _onCrossfadeTick() {
    if (!_isCrossfading || _fadeTickStartTime == null) return;

    final now = DateTime.now();
    final tickElapsed = now.difference(_fadeTickStartTime!);
    _fadeTickStartTime = now;
    _accumulatedFadeDuration += tickElapsed;

    final totalMs = _effectiveCrossfadeDuration.inMilliseconds;
    final progress = totalMs > 0
        ? (_accumulatedFadeDuration.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 1.0;

    final vOut = _crossfadeConfig.calculateFadeOutVolume(
      progress,
      _masterVolume,
    );
    final vIn = _crossfadeConfig.calculateFadeInVolume(progress, _masterVolume);

    _activePlayer.setVolume(vOut);
    _standbyPlayer.setVolume(vIn);

    if (progress >= 1.0) {
      _completeCrossfade();
    }
  }

  Future<void> _completeCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeTickStartTime = null;
    _accumulatedFadeDuration = Duration.zero;

    // Terminate outgoing player
    await _activePlayer.stop();

    // Ensure incoming player receives exact master volume
    await _standbyPlayer.setVolume(_masterVolume);

    // Only auto-crossfade advances queue index at completion
    if (!_isManualCrossfade) {
      _advanceQueueIndex();
    }

    // Role Swap: Standby becomes Active, Active becomes Standby
    final temp = _activePlayer;
    _activePlayer = _standbyPlayer;
    _standbyPlayer = temp;

    _isCrossfading = false;
    _isManualCrossfade = false;
    _bindActivePlayerStreams();
    _emitState();
  }

  Future<void> _fastForwardCrossfade() async {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeTickStartTime = null;
    _accumulatedFadeDuration = Duration.zero;

    await _activePlayer.stop();
    await _standbyPlayer.setVolume(_masterVolume);

    if (!_isManualCrossfade) {
      _advanceQueueIndex();
    }

    final temp = _activePlayer;
    _activePlayer = _standbyPlayer;
    _standbyPlayer = temp;

    _isCrossfading = false;
    _isManualCrossfade = false;
    _bindActivePlayerStreams();
    _emitState();
  }

  void _abortActiveCrossfade() {
    if (!_isCrossfading) return;

    _fadeTimer?.cancel();
    _fadeTimer = null;
    _fadeTickStartTime = null;
    _accumulatedFadeDuration = Duration.zero;
    _isCrossfading = false;
    _isManualCrossfade = false;

    // Reset outgoing player back to full master volume
    _activePlayer.setVolume(_masterVolume);
    // Stop preloaded standby player
    _standbyPlayer.stop();
  }

  void _advanceQueueIndex() {
    if (_queueManager.loopMode == Loop.one) {
      // Index remains unchanged
    } else if (_queueManager.currentIndex <
        _queueManager.activeQueue.length - 1) {
      _queueManager.jumpTo(_queueManager.currentIndex + 1);
    } else if (_queueManager.loopMode == Loop.all) {
      _queueManager.jumpTo(0);
    }
  }

  Future<void> _handleTrackCompleted() async {
    if (_queueManager.loopMode == Loop.one) {
      await _activePlayer.seek(Duration.zero);
      await _activePlayer.play();
      _emitState();
    } else {
      final nextItem = await _queueManager.next(isManual: false);
      if (nextItem != null) {
        await _activePlayer.open(nextItem.filePath, play: true);
        _emitState();
      } else {
        await _activePlayer.stop();
        _stateSubject.add(
          currentState.copyWith(completed: true, playing: false),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // Audio Effects & MPV Controls
  // --------------------------------------------------------------------------

  Future<void> setVolume(double volume) async {
    _masterVolume = volume.clamp(
      AppDefaults.volumeMin,
      AppDefaults.volumeBoostMax,
    );
    if (!_isCrossfading) {
      await _activePlayer.setVolume(_masterVolume);
    }
    _emitState();
  }

  Future<void> setRate(double rate) async {
    _playbackRate = rate.clamp(
      AppDefaults.playbackRateMin,
      AppDefaults.playbackRateMax,
    );
    await _activePlayer.setRate(_playbackRate);
    await _standbyPlayer.setRate(_playbackRate);
    _emitState();
  }

  Future<void> setPitch(double pitch) async {
    _playbackPitch = pitch.clamp(
      AppDefaults.playbackPitchMin,
      AppDefaults.playbackPitchMax,
    );
    await _activePlayer.setPitch(_playbackPitch);
    await _standbyPlayer.setPitch(_playbackPitch);
    _emitState();
  }

  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    await _activePlayer.setSkipSilence(enabled);
    await _standbyPlayer.setSkipSilence(enabled);
    _emitState();
  }

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    await _playerA.setEqualizer(equalizer);
    await _playerB.setEqualizer(equalizer);
  }

  Future<bool> setDevice(AudioDevice device) async {
    _currentDevice = device;
    final resA = await _playerA.setDevice(device);
    final resB = await _playerB.setDevice(device);
    return resA || resB;
  }

  Future<List<AudioDevice>> getAudioDevices() => _activePlayer.getAudioDevices();

  // --------------------------------------------------------------------------
  // Queue Management Delegation
  // --------------------------------------------------------------------------

  Future<void> setLoopMode(Loop loop) async {
    _queueManager.setLoopMode(loop);
    _emitState();
  }

  Future<void> toggleShuffle() async {
    _queueManager.toggleShuffle();
    _emitState();
  }

  Future<void> insertNext(QueueItem playable) async {
    if (_isCrossfading) {
      _abortActiveCrossfade();
    }
    if (_queueManager.activeQueue.isEmpty) {
      await open([playable]);
      return;
    }
    _queueManager.insertNext(playable);
    _emitState();
  }

  Future<void> append(List<QueueItem> playables) async {
    if (_queueManager.activeQueue.isEmpty) {
      await open(playables);
      return;
    }
    _queueManager.append(playables);
    _emitState();
  }

  Future<void> remove(int index) async {
    if (index < 0 || index >= _queueManager.activeQueue.length) return;

    if (_isCrossfading) {
      _abortActiveCrossfade();
    }

    final wasCurrent = index == _queueManager.currentIndex;
    _queueManager.remove(index);

    if (_queueManager.activeQueue.isEmpty) {
      await stop();
    } else if (wasCurrent && _queueManager.currentTrack != null) {
      await _activePlayer.open(_queueManager.currentTrack!.filePath, play: true);
    }
    _emitState();
  }

  Future<void> reorder(int from, int to) async {
    if (_isCrossfading) {
      _abortActiveCrossfade();
    }
    _queueManager.reorder(from, to);
    _emitState();
  }

  Future<void> dispose() async {
    _abortActiveCrossfade();
    for (final sub in _activeSubscriptions) {
      await sub.cancel();
    }
    await _activePlayer.dispose();
    await _standbyPlayer.dispose();
    await _stateSubject.close();
  }
}
