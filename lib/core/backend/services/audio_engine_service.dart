import 'dart:async';
import 'dart:math' as math;

import 'package:miniaudio_player/miniaudio_player.dart' show AudioDevice, Equalizer;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/playback/domain/behavior_subject.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart' show CrossfadeCurve;

import 'audio_player_adapter.dart';
import 'crossfade_manager.dart';
import 'queue_manager.dart';

/// Clean, robust audio engine service orchestrating playback, queue, and seamless crossfading.
///
/// Architecture:
/// - Maintains dual audio players (_playerA, _playerB) with clean role semantics:
///   `_activePlayer`: The primary player reflecting current track position to the UI.
///   `_standbyPlayer`: The secondary player used for crossfade preparation and transitions.
/// - Crossfade is treated as a pure audio transition effect:
///   Canceling a crossfade simply stops the effect, silences/stops `_standbyPlayer`,
///   and restores `_activePlayer` to master volume.
class AudioEngineService {
  final AudioPlayerAdapter _playerA;
  final AudioPlayerAdapter _playerB;
  late AudioPlayerAdapter _activePlayer;
  late AudioPlayerAdapter _standbyPlayer;

  final QueueManager _queueManager;
  final CrossfadeManager _crossfadeManager;
  final Duration tickerInterval;

  final BehaviorSubject<PlaybackState> _stateSubject;
  final StreamController<Duration> _positionStreamController =
      StreamController<Duration>.broadcast();
  final List<StreamSubscription> _activeSubscriptions = [];
  StreamSubscription<bool>? _completedSubscription;
  int? _lastHandledTrackIndex;

  CrossfadeConfig _crossfadeConfig = const CrossfadeConfig();
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
    CrossfadeManager? crossfadeManager,
    this.tickerInterval = const Duration(milliseconds: 25),
    math.Random? random,
  })  : _playerA = playerA ?? AudioPlayerAdapter(),
        _playerB = playerB ?? AudioPlayerAdapter(),
        _queueManager = queueManager ?? QueueManager(random: random),
        _crossfadeManager = crossfadeManager ??
            CrossfadeManager(tickerInterval: tickerInterval),
        _stateSubject = BehaviorSubject<PlaybackState>(
          const PlaybackState.initial(),
        ) {
    _activePlayer = _playerA;
    _standbyPlayer = _playerB;
    _bindActivePlayerStreams();
  }

  // --------------------------------------------------------------------------
  // Public Accessors
  // --------------------------------------------------------------------------

  AudioPlayerAdapter get activePlayer => _activePlayer;
  AudioPlayerAdapter get standbyPlayer => _standbyPlayer;
  QueueManager get queueManager => _queueManager;
  bool get isCrossfading => _crossfadeManager.isActive;
  CrossfadeConfig get crossfadeConfig => _crossfadeConfig;
  Equalizer get equalizer => _equalizer;
  AudioDevice? get currentDevice => _currentDevice;
  bool get isPlaying => _activePlayer.isPlaying;

  Stream<PlaybackState> get stateStream => _stateSubject;
  Stream<Duration> get positionStream => _positionStreamController.stream;
  PlaybackState get currentState => _stateSubject.value;
  PlaybackState get state => _stateSubject.value;

  // --------------------------------------------------------------------------
  // Core Playback Operations
  // --------------------------------------------------------------------------

  Future<void> open(
    List<QueueItem> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    await _cancelCrossfade();
    _lastHandledTrackIndex = null;
    try {
      await _standbyPlayer.setVolume(0.0);
      await _standbyPlayer.stop();
    } catch (_) {}

    if (playables.isEmpty) {
      _queueManager.clear();
      try {
        await _activePlayer.stop();
      } catch (_) {}
      _emitState();
      return;
    }

    _queueManager.setQueue(playables, startIndex: index, shuffle: shuffle);
    final targetTrack = _queueManager.currentTrack;
    if (targetTrack == null) {
      _emitState();
      return;
    }

    await _configurePlayerProperties(_activePlayer);
    await _activePlayer.setVolume(_masterVolume);
    await _activePlayer.open(targetTrack.filePath, play: play);
    await _activePlayer.seek(Duration.zero);

    _emitState();
  }

  Future<void> play() async {
    if (_queueManager.activeQueue.isEmpty) return;
    if (_crossfadeManager.isActive) {
      await _crossfadeManager.resume();
    } else {
      await _activePlayer.play();
    }
    _emitState();
  }

  Future<void> pause() async {
    if (_crossfadeManager.isActive) {
      await _crossfadeManager.pause();
    } else {
      await _activePlayer.pause();
    }
    _emitState();
  }

  Future<void> stop() async {
    await _cancelCrossfade();
    _lastHandledTrackIndex = null;
    try {
      await _standbyPlayer.setVolume(0.0);
      await _standbyPlayer.stop();
    } catch (_) {}
    try {
      await _activePlayer.stop();
    } catch (_) {}
    _emitState();
  }

  Future<void> seek(Duration position) async {
    if (_queueManager.activeQueue.isEmpty) return;

    final wasPlaying = _activePlayer.isPlaying || currentState.playing;

    await _cancelCrossfade();
    _lastHandledTrackIndex = null;
    _bindActivePlayerStreams();

    await _activePlayer.seek(position);
    if (wasPlaying && !_activePlayer.isPlaying) {
      await _activePlayer.play();
    }
    _emitState();
  }

  Future<void> next() async {
    if (_queueManager.activeQueue.isEmpty) return;
    _lastHandledTrackIndex = null;

    if (_queueManager.loopMode == Loop.one) {
      await _activePlayer.seek(Duration.zero);
      await _activePlayer.play();
      _emitState();
      return;
    }

    final nextItem = await _queueManager.next(isManual: true);
    if (nextItem != null) {
      await _executeManualTransition(nextItem);
    } else {
      await stop();
      _stateSubject.add(currentState.copyWith(completed: true, playing: false));
    }
  }

  Future<void> previous() async {
    if (_queueManager.activeQueue.isEmpty) return;
    _lastHandledTrackIndex = null;

    // Standard behavior: if current track has played > 3 seconds, restart it
    if (_activePlayer.position > const Duration(seconds: 3)) {
      await _cancelCrossfade();
      _bindActivePlayerStreams();
      await _activePlayer.seek(Duration.zero);
      _emitState();
      return;
    }

    final prevItem = _queueManager.previous(position: _activePlayer.position);
    if (prevItem != null) {
      await _executeManualTransition(prevItem);
    } else {
      await _activePlayer.seek(Duration.zero);
      _emitState();
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index < 0 || index >= _queueManager.activeQueue.length) return;
    _lastHandledTrackIndex = null;

    final targetItem = _queueManager.jumpTo(index);
    if (targetItem != null) {
      await _executeManualTransition(targetItem);
    }
  }

  Future<void> clearQueue() async {
    await open([]);
  }

  // --------------------------------------------------------------------------
  // Clean Crossfade Cancellation & Transitions
  // --------------------------------------------------------------------------

  Future<void> _cancelCrossfade() async {
    if (!_crossfadeManager.isActive) return;
    _crossfadeManager.cancel();

    try {
      await _standbyPlayer.setVolume(0.0);
      await _standbyPlayer.stop();
    } catch (_) {}

    try {
      await _activePlayer.setVolume(_masterVolume);
    } catch (_) {}
  }

  Future<void> _executeManualTransition(QueueItem targetTrack) async {
    final manualDuration = _crossfadeConfig.manualDuration;
    final canCrossfade = _crossfadeConfig.enabled &&
        manualDuration > Duration.zero &&
        _activePlayer.isPlaying;

    _completedSubscription?.cancel();
    _completedSubscription = null;

    if (!canCrossfade) {
      await _cancelCrossfade();
      await _activePlayer.open(targetTrack.filePath, play: true);
      await _activePlayer.seek(Duration.zero);
      _bindActivePlayerStreams();
      _emitState();
      return;
    }

    // Cancel prior transition cleanly
    await _cancelCrossfade();

    // 1. Prepare standby player with new track
    await _configurePlayerProperties(_standbyPlayer);
    await _standbyPlayer.open(targetTrack.filePath, play: true);
    await _standbyPlayer.seek(Duration.zero);

    // 2. Immediate role swap: UI and streams instantly follow incoming track
    final outgoingPlayer = _activePlayer;
    _activePlayer = _standbyPlayer;
    _standbyPlayer = outgoingPlayer;

    _bindActivePlayerStreams();
    _emitState();

    // 3. Launch crossfade
    final effectiveDuration = _clampCrossfadeDuration(
      outgoingDuration: outgoingPlayer.duration,
      outgoingRemaining: outgoingPlayer.duration - outgoingPlayer.position,
      targetDuration: manualDuration,
      incomingDuration: _activePlayer.duration,
    );

    await _crossfadeManager.cross(
      playerOut: outgoingPlayer,
      playerIn: _activePlayer,
      targetDuration: effectiveDuration,
      curve: _crossfadeConfig.curve,
      masterVolume: _masterVolume,
      onCrossEnd: () {
        _emitState();
      },
    );
  }

  void _checkCrossfadeTrigger(Duration currentPosition, Duration totalDuration) {
    if (_crossfadeManager.isActive) return;
    if (!_crossfadeConfig.enabled || _crossfadeConfig.duration == Duration.zero) return;
    if (totalDuration <= Duration.zero) return;

    final remaining = totalDuration - currentPosition;
    if (remaining <= Duration.zero) return;

    final nextTrack = _getNextTrackForAutoCrossfade();
    if (nextTrack == null) return;

    final effectiveDuration = _clampCrossfadeDuration(
      outgoingDuration: totalDuration,
      outgoingRemaining: remaining,
      targetDuration: _crossfadeConfig.duration,
      incomingDuration: nextTrack.duration,
    );

    if (effectiveDuration <= Duration.zero) return;

    if (remaining <= effectiveDuration) {
      _startAutoCrossfade(effectiveDuration, nextTrack);
    }
  }

  Future<void> _startAutoCrossfade(Duration effectiveDuration, QueueItem nextTrack) async {
    _completedSubscription?.cancel();
    _completedSubscription = null;

    // 1. Preload standby player with next track at zero volume
    await _configurePlayerProperties(_standbyPlayer);
    await _standbyPlayer.setVolume(0.0);
    await _standbyPlayer.open(nextTrack.filePath, play: true);
    await _standbyPlayer.seek(Duration.zero);

    final outgoingPlayer = _activePlayer;
    final incomingPlayer = _standbyPlayer;

    // 2. Delegate crossfade transition to CrossfadeManager
    await _crossfadeManager.cross(
      playerOut: outgoingPlayer,
      playerIn: incomingPlayer,
      targetDuration: effectiveDuration,
      curve: _crossfadeConfig.curve,
      masterVolume: _masterVolume,
      onCrossEnd: () {
        _handleAutoCrossfadeEnd(incomingPlayer, outgoingPlayer);
      },
    );
  }

  void _handleAutoCrossfadeEnd(
    AudioPlayerAdapter incomingPlayer,
    AudioPlayerAdapter outgoingPlayer,
  ) {
    // Verify player assignment has not been superseded
    if (_standbyPlayer != incomingPlayer) return;

    // Advance queue index
    _advanceQueueIndex();

    // Swap roles: incoming becomes active, outgoing becomes standby
    _activePlayer = incomingPlayer;
    _standbyPlayer = outgoingPlayer;

    _bindActivePlayerStreams();
    _emitState();
  }

  Duration _clampCrossfadeDuration({
    required Duration outgoingDuration,
    required Duration outgoingRemaining,
    required Duration targetDuration,
    required Duration incomingDuration,
  }) {
    var dur = targetDuration;
    if (outgoingRemaining > Duration.zero && outgoingRemaining < dur) {
      dur = outgoingRemaining;
    }
    if (outgoingDuration > Duration.zero) {
      final halfOutgoing = Duration(milliseconds: outgoingDuration.inMilliseconds ~/ 2);
      if (halfOutgoing > Duration.zero && dur > halfOutgoing) {
        dur = halfOutgoing;
      }
    }
    if (incomingDuration > Duration.zero) {
      final halfIncoming = Duration(milliseconds: incomingDuration.inMilliseconds ~/ 2);
      if (halfIncoming > Duration.zero && dur > halfIncoming) {
        dur = halfIncoming;
      }
    }
    return dur;
  }

  QueueItem? _getNextTrackForAutoCrossfade() {
    if (_queueManager.activeQueue.isEmpty) return null;
    if (_queueManager.loopMode == Loop.one) return null;

    if (_queueManager.currentIndex < _queueManager.activeQueue.length - 1) {
      return _queueManager.activeQueue[_queueManager.currentIndex + 1];
    }
    if (_queueManager.loopMode == Loop.all) {
      return _queueManager.activeQueue[0];
    }
    return null;
  }

  void _advanceQueueIndex() {
    if (_queueManager.loopMode == Loop.one) return;

    if (_queueManager.currentIndex < _queueManager.activeQueue.length - 1) {
      _queueManager.jumpTo(_queueManager.currentIndex + 1);
    } else if (_queueManager.loopMode == Loop.all) {
      _queueManager.jumpTo(0);
    }
  }

  Future<void> _handleTrackCompleted() async {
    final currentIdx = _queueManager.currentIndex;
    if (currentIdx == _lastHandledTrackIndex) return;
    _lastHandledTrackIndex = currentIdx;

    if (_queueManager.loopMode == Loop.one) {
      await _activePlayer.seek(Duration.zero);
      await _activePlayer.play();
      _emitState();
    } else {
      final nextItem = await _queueManager.next(isManual: false);
      if (nextItem != null) {
        await _activePlayer.open(nextItem.filePath, play: true);
        await _activePlayer.seek(Duration.zero);
        _emitState();
      } else {
        await _activePlayer.stop();
        _stateSubject.add(currentState.copyWith(completed: true, playing: false));
      }
    }
  }

  // --------------------------------------------------------------------------
  // Stream & State Management
  // --------------------------------------------------------------------------

  void _bindActivePlayerStreams() {
    for (final sub in _activeSubscriptions) {
      sub.cancel();
    }
    _activeSubscriptions.clear();
    _completedSubscription?.cancel();
    _completedSubscription = null;

    _activeSubscriptions.add(
      _activePlayer.positionStream.listen((pos) {
        _positionStreamController.add(pos);
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

    // Dedicated completed subscription. Disconnected during any crossfade transition.
    _completedSubscription = _activePlayer.completedStream.listen((completed) {
      if (completed && !_crossfadeManager.isActive) {
        _handleTrackCompleted();
      }
    });
  }

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

  Future<void> _configurePlayerProperties(AudioPlayerAdapter player) async {
    try {
      await player.setRate(_playbackRate);
      await player.setPitch(_playbackPitch);
      await player.setEqualizer(_equalizer);
      await player.setSkipSilence(_skipSilence);
      if (_currentDevice != null) {
        await player.setDevice(_currentDevice!);
      }
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // Audio Configuration Controls
  // --------------------------------------------------------------------------

  Future<void> setVolume(double volume) async {
    _masterVolume = volume.clamp(AppDefaults.volumeMin, AppDefaults.volumeBoostMax);
    if (_crossfadeManager.isActive) {
      _crossfadeManager.setMasterVolume(_masterVolume);
    } else {
      await _activePlayer.setVolume(_masterVolume);
    }
    _emitState();
  }

  Future<void> setRate(double rate) async {
    _playbackRate = rate.clamp(AppDefaults.playbackRateMin, AppDefaults.playbackRateMax);
    await _activePlayer.setRate(_playbackRate);
    await _standbyPlayer.setRate(_playbackRate);
    _emitState();
  }

  Future<void> setPitch(double pitch) async {
    _playbackPitch = pitch.clamp(AppDefaults.playbackPitchMin, AppDefaults.playbackPitchMax);
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

  Future<void> setCrossfadeDuration(Duration duration) async {
    _crossfadeConfig = _crossfadeConfig.copyWith(duration: duration);
    _emitState();
  }

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async {
    _crossfadeConfig = _crossfadeConfig.copyWith(curve: curve);
    _emitState();
  }

  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    _crossfadeConfig = config;
    _emitState();
  }

  // --------------------------------------------------------------------------
  // Queue Management Delegation
  // --------------------------------------------------------------------------

  Future<void> setShuffle(bool enabled) async {
    if (_queueManager.isShuffled != enabled) {
      await toggleShuffle();
    }
  }

  Future<void> toggleShuffle() async {
    _queueManager.toggleShuffle();
    _emitState();
  }

  Future<void> setLoopMode(Loop loop) async {
    _queueManager.setLoopMode(loop);
    _emitState();
  }

  Future<void> insertNext(QueueItem playable) async {
    await _cancelCrossfade();
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

    await _cancelCrossfade();

    final wasCurrent = index == _queueManager.currentIndex;
    _queueManager.remove(index);

    if (_queueManager.activeQueue.isEmpty) {
      await stop();
    } else if (wasCurrent && _queueManager.currentTrack != null) {
      await _activePlayer.open(_queueManager.currentTrack!.filePath, play: true);
      await _activePlayer.seek(Duration.zero);
    }
    _emitState();
  }

  Future<void> reorder(int from, int to) async {
    await _cancelCrossfade();
    _queueManager.reorder(from, to);
    _emitState();
  }

  // --------------------------------------------------------------------------
  // Cleanup
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    await _cancelCrossfade();
    _completedSubscription?.cancel();
    _completedSubscription = null;
    for (final sub in _activeSubscriptions) {
      await sub.cancel();
    }
    _activeSubscriptions.clear();
    await _activePlayer.dispose();
    await _standbyPlayer.dispose();
    await _positionStreamController.close();
    await _stateSubject.close();
  }
}
