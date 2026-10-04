import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
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

/// Kind of an in-flight transition between the two players.
enum _TransitionKind {
  /// Tentative transition started by the position ticker near the end of a
  /// track. The queue is NOT advanced until the crossfade completes; aborting
  /// it reverts to the outgoing track.
  auto,

  /// Transition requested by the user (next/previous/skip). The queue and the
  /// player roles are already committed; aborting it jumps to the end state.
  manual,
}

class _Transition {
  _Transition({
    required this.kind,
    required this.target,
    required this.outgoing,
    required this.incoming,
  });

  _TransitionKind kind;
  final QueueItem target;
  final AudioPlayerAdapter outgoing;
  final AudioPlayerAdapter incoming;
}

/// Audio engine: executes playback decisions on two players.
///
/// Separation of roles:
/// - [QueueManager] decides **what** plays (current/next item, repeat modes,
///   restart-vs-previous policy, commit of tentative transitions).
/// - [CrossfadeManager] performs the volume envelope between two players.
/// - [AudioEngineService] decides **how** it plays (load, hard cut or
///   crossfade) and owns the player roles (`_activePlayer` / `_standbyPlayer`).
///
/// Concurrency model:
/// - Every command that touches player roles, the standby player or the queue
///   runs through a single FIFO lane ([_serialize]). Internal events
///   (track completion, auto-crossfade trigger) are scheduled on the same
///   lane, so no two transitions can ever interleave across `await` points.
/// - Synchronous events that must react immediately (queue candidate changes,
///   crossfade completion) are validated against the identity of the current
///   [_Transition], so stale callbacks are ignored.
/// - Player events are only honoured when they come from the current active
///   player and the current playback session ([_playbackSession]).
class AudioEngineService {
  /// Minimum interval between full [PlaybackState] emissions caused purely by
  /// position updates. Smooth position goes through [positionStream]; the
  /// full state (which carries the whole queue) must not be re-sent on every
  /// tick across isolates.
  static const Duration _positionStateInterval = Duration(seconds: 1);

  /// Tolerance used to decide whether a `completed` event is genuine (the
  /// player is really at the end) or a stale event delivered after a seek.
  static const Duration _completionTolerance = Duration(seconds: 1);

  final AudioPlayerAdapter _playerA;
  final AudioPlayerAdapter _playerB;
  late AudioPlayerAdapter _activePlayer;
  late AudioPlayerAdapter _standbyPlayer;

  final QueueManager _queueManager;
  final bool _ownsQueueManager;
  final CrossfadeManager _crossfadeManager;
  final Duration tickerInterval;

  final BehaviorSubject<PlaybackState> _stateSubject;
  final StreamController<Duration> _positionStreamController =
      StreamController<Duration>.broadcast();
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];
  StreamSubscription<QueueItem?>? _queueSubscription;

  /// Tail of the serialized command lane.
  Future<void> _commandTail = Future<void>.value();
  bool _disposed = false;

  /// The single in-flight transition, if any.
  _Transition? _transition;

  /// Pending volume/stop commands issued by the last transition abort.
  Future<void> _pendingRestore = Future<void>.value();

  /// Incremented whenever the active player is (re)loaded, seeked or swapped.
  /// Player events captured under an older session are ignored.
  int _playbackSession = 0;

  bool _autoStartScheduled = false;
  QueueItem? _failedAutoTarget;
  bool _queueEnded = false;
  DateTime? _lastStateEmit;

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
        _ownsQueueManager = queueManager == null,
        _crossfadeManager = crossfadeManager ??
            CrossfadeManager(tickerInterval: tickerInterval),
        _stateSubject = BehaviorSubject<PlaybackState>(
          const PlaybackState.initial(),
        ) {
    _activePlayer = _playerA;
    _standbyPlayer = _playerB;
    _bindActivePlayer();
    _queueSubscription =
        _queueManager.nextTrackStream.listen(_onNextCandidateChanged);
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

  /// Last emitted state (position may lag up to [_positionStateInterval]).
  PlaybackState get currentState => _stateSubject.value;

  /// Snapshot of the state with the live position of the active player.
  PlaybackState get state =>
      _stateSubject.value.copyWith(position: _activePlayer.position);

  // --------------------------------------------------------------------------
  // Core Playback Commands (serialized)
  // --------------------------------------------------------------------------

  Future<void> open(
    List<QueueItem> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) =>
      _serialize(
        () => _openImpl(playables, index: index, play: play, shuffle: shuffle),
      );

  Future<void> play() => _serialize(() async {
        if (_queueManager.isEmpty) return;
        _queueEnded = false;
        if (_crossfadeManager.isActive) {
          await _crossfadeManager.resume();
        } else {
          await _activePlayer.play();
        }
        _emitState();
      });

  Future<void> pause() => _serialize(() async {
        if (_crossfadeManager.isActive) {
          await _crossfadeManager.pause();
        } else {
          await _activePlayer.pause();
        }
        _emitState();
      });

  Future<void> stop() => _serialize(() async {
        await _abortTransition();
        await _stopPlayers();
        _emitState();
      });

  Future<void> seek(Duration position) => _serialize(() async {
        if (_queueManager.isEmpty) return;
        final wasPlaying = _activePlayer.isPlaying || currentState.playing;

        await _abortTransition();
        _bumpSession();
        _queueEnded = false;

        await _activePlayer.seek(position);
        if (wasPlaying && !_activePlayer.isPlaying) {
          await _activePlayer.play();
        }
        _emitState();
      });

  Future<void> next() => _serialize(() async {
        if (_queueManager.isEmpty) return;

        // The user skips while an automatic crossfade towards the very same
        // next track is running: commit it instead of restarting the fade.
        if (_promoteAutoTransition()) return;

        await _abortTransition();
        final before = _queueManager.currentTrack;
        final target = await _queueManager.next(isManual: true);
        if (target == null) {
          await _endOfQueue();
        } else if (identical(target, before)) {
          await _restartCurrent(play: true);
        } else {
          await _playTarget(target, play: true, crossfade: true);
        }
      });

  Future<void> previous() => _serialize(() async {
        if (_queueManager.isEmpty) return;
        final wasPlaying = _activePlayer.isPlaying || currentState.playing;

        // Restart-vs-previous is the queue's policy; it returns null when the
        // current track must be restarted.
        final target = _queueManager.previous(position: _activePlayer.position);
        if (target == null) {
          await _restartCurrent(play: wasPlaying);
        } else {
          await _playTarget(target, play: wasPlaying, crossfade: true);
        }
      });

  Future<void> skipToIndex(int index, {bool? play}) => _serialize(() async {
        if (index < 0 || index >= _queueManager.length) return;
        final shouldPlay = play ?? (_activePlayer.isPlaying || currentState.playing || true);
        final before = _queueManager.currentTrack;
        final target = _queueManager.jumpTo(index);
        if (target == null) return;
        if (identical(target, before)) {
          await _restartCurrent(play: shouldPlay);
        } else {
          await _playTarget(target, play: shouldPlay, crossfade: true);
        }
      });

  Future<void> clearQueue() => open(const []);

  // --------------------------------------------------------------------------
  // Queue Mutation Commands (serialized)
  //
  // The engine never inspects indices to decide whether a tentative crossfade
  // is still valid: QueueManager.nextTrackStream notifies candidate changes
  // synchronously and [_onNextCandidateChanged] aborts it if needed.
  // --------------------------------------------------------------------------

  Future<void> setShuffle(bool enabled) => _serialize(() async {
        _queueManager.setShuffle(enabled);
        await _settle();
        _emitState();
      });

  Future<void> toggleShuffle() => _serialize(() async {
        _queueManager.toggleShuffle();
        await _settle();
        _emitState();
      });

  Future<void> setLoopMode(Loop loop) => _serialize(() async {
        _queueManager.setLoopMode(loop);
        await _settle();
        _emitState();
      });

  Future<void> setInfiniteMix(bool enabled) => _serialize(() async {
        _queueManager.setInfiniteMix(enabled);
        _emitState();
      });

  Future<void> insertNext(QueueItem playable) => _serialize(() async {
        if (_queueManager.isEmpty) {
          await _openImpl([playable]);
          return;
        }
        _queueManager.insertNext(playable);
        await _settle();
        _emitState();
      });

  Future<void> append(List<QueueItem> playables) => _serialize(() async {
        if (playables.isEmpty) return;
        if (_queueManager.isEmpty) {
          await _openImpl(playables);
          return;
        }
        _queueManager.append(playables);
        await _settle();
        _emitState();
      });

  Future<void> remove(int index) => _serialize(() async {
        if (index < 0 || index >= _queueManager.length) return;

        final before = _queueManager.currentTrack;
        final wasPlaying = _activePlayer.isPlaying;
        _queueManager.remove(index);
        await _settle();

        if (_queueManager.isEmpty) {
          await _abortTransition();
          await _stopPlayers();
          _emitState();
          return;
        }

        final after = _queueManager.currentTrack;
        if (after != null && !identical(after, before)) {
          // The current item was removed: the queue already selected the
          // replacement, the engine just loads it (no crossfade).
          await _playTarget(after, play: wasPlaying, crossfade: false);
          return;
        }
        _emitState();
      });

  Future<void> reorder(int from, int to) => _serialize(() async {
        _queueManager.reorder(from, to);
        await _settle();
        _emitState();
      });

  // --------------------------------------------------------------------------
  // Audio Configuration Controls
  //
  // These only set idempotent player properties (no role/queue changes), so
  // they bypass the command lane to stay responsive (e.g. volume sliders).
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
    if (_crossfadeManager.isActive) {
      _crossfadeManager.setPlaybackRate(_playbackRate);
    }
    await Future.wait([
      _playerA.setRate(_playbackRate),
      _playerB.setRate(_playbackRate),
    ]);
    _emitState();
  }

  Future<void> setPitch(double pitch) async {
    _playbackPitch = pitch.clamp(AppDefaults.playbackPitchMin, AppDefaults.playbackPitchMax);
    await Future.wait([
      _playerA.setPitch(_playbackPitch),
      _playerB.setPitch(_playbackPitch),
    ]);
    _emitState();
  }

  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    await Future.wait([
      _playerA.setSkipSilence(enabled),
      _playerB.setSkipSilence(enabled),
    ]);
    _emitState();
  }

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    await Future.wait([
      _playerA.setEqualizer(equalizer),
      _playerB.setEqualizer(equalizer),
    ]);
  }

  Future<bool> setDevice(AudioDevice device) async {
    _currentDevice = device;
    final results = await Future.wait([
      _playerA.setDevice(device),
      _playerB.setDevice(device),
    ]);
    return results.any((ok) => ok);
  }

  Future<List<AudioDevice>> getAudioDevices() => _activePlayer.getAudioDevices();

  Future<void> setCrossfadeDuration(Duration duration) => _serialize(() async {
        _crossfadeConfig = _crossfadeConfig.copyWith(duration: duration);
        await _abortAutoTransitionIfDisabled();
        _emitState();
      });

  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async {
    _crossfadeConfig = _crossfadeConfig.copyWith(curve: curve);
    _emitState();
  }

  Future<void> setCrossfadeConfig(CrossfadeConfig config) => _serialize(() async {
        _crossfadeConfig = config;
        await _abortAutoTransitionIfDisabled();
        _emitState();
      });

  // --------------------------------------------------------------------------
  // Command Lane
  // --------------------------------------------------------------------------

  /// Runs [action] after every previously queued command has finished.
  ///
  /// Errors propagate to the caller but never break the lane.
  Future<void> _serialize(Future<void> Function() action) {
    if (_disposed) return Future<void>.value();
    final run = _commandTail.then<void>((_) async {
      if (_disposed) return;
      await action();
    });
    _commandTail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Fire-and-forget variant of [_serialize] for internal events.
  void _schedule(Future<void> Function() action) {
    unawaited(
      _serialize(action).catchError((Object e, StackTrace s) {
        debugPrint('[AudioEngine] Internal task failed: $e\n$s');
      }),
    );
  }

  /// Waits for volume/stop commands issued by a pending transition abort.
  Future<void> _settle() => _pendingRestore;

  // --------------------------------------------------------------------------
  // Command Implementations (must only run inside the lane)
  // --------------------------------------------------------------------------

  Future<void> _openImpl(
    List<QueueItem> playables, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    await _abortTransition();
    await _silence(_standbyPlayer);

    if (playables.isEmpty) {
      _queueManager.clear();
      await _stopPlayers();
      _emitState();
      return;
    }

    _queueManager.setQueue(playables, startIndex: index, shuffle: shuffle);
    final target = _queueManager.currentTrack;
    if (target == null) {
      _emitState();
      return;
    }
    await _playTarget(target, play: play, crossfade: false);
  }

  /// Loads [target] (hard cut or manual crossfade). If a track cannot be
  /// opened, the queue is asked for the next one, bounded by the queue length
  /// so a fully broken queue cannot loop forever.
  Future<void> _playTarget(
    QueueItem target, {
    required bool play,
    required bool crossfade,
  }) async {
    await _abortTransition();
    _queueEnded = false;

    var candidate = target;
    final maxAttempts = math.max(1, _queueManager.length);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final useCrossfade = crossfade && play && _canManualCrossfade();
      final ok = useCrossfade
          ? await _crossfadeTo(candidate)
          : await _hardLoad(candidate, play: play);
      if (ok) return;

      debugPrint('[AudioEngine] Skipping unplayable track: ${candidate.filePath}');
      final skipped = await _queueManager.next(isManual: true);
      if (skipped == null || identical(skipped, candidate)) break;
      candidate = skipped;
    }

    await _endOfQueue();
  }

  bool _canManualCrossfade() =>
      _crossfadeConfig.enabled &&
      _crossfadeConfig.manualDuration > Duration.zero &&
      _activePlayer.isPlaying;

  Future<bool> _hardLoad(QueueItem item, {required bool play}) async {
    _bumpSession();
    final ok = await _openOn(
      _activePlayer,
      item,
      play: play,
      volume: _masterVolume,
    );
    _emitState();
    return ok;
  }

  Future<bool> _crossfadeTo(QueueItem item) async {
    final outgoing = _activePlayer;
    final incoming = _standbyPlayer;

    if (!await _openOn(incoming, item, play: false, volume: 0.0)) {
      await _silence(incoming);
      return false;
    }

    // Manual transitions are committed immediately: the queue already points
    // at [item], so the UI and the streams follow the incoming player.
    final transition = _Transition(
      kind: _TransitionKind.manual,
      target: item,
      outgoing: outgoing,
      incoming: incoming,
    );
    _transition = transition;
    _activePlayer = incoming;
    _standbyPlayer = outgoing;
    _bumpSession();
    _bindActivePlayer();

    final duration = _clampCrossfadeDuration(
      outgoingDuration: outgoing.duration,
      outgoingRemaining: outgoing.duration - outgoing.position,
      targetDuration: _crossfadeConfig.manualDuration,
      incomingDuration:
          incoming.duration > Duration.zero ? incoming.duration : item.duration,
    );

    await _crossfadeManager.cross(
      playerOut: outgoing,
      playerIn: incoming,
      targetDuration: duration,
      curve: _crossfadeConfig.curve,
      masterVolume: _masterVolume,
      playbackRate: _playbackRate,
      onCrossEnd: () => _onCrossEnd(transition),
    );
    _emitState();
    return true;
  }

  Future<void> _restartCurrent({required bool play}) async {
    await _abortTransition();
    _bumpSession();
    _queueEnded = false;
    await _activePlayer.seek(Duration.zero);
    if (play && !_activePlayer.isPlaying) {
      await _activePlayer.play();
    }
    _emitState();
  }

  Future<void> _endOfQueue() async {
    await _abortTransition();
    await _stopPlayers();
    _queueEnded = true;
    _emitState();
  }

  Future<void> _stopPlayers() async {
    _bumpSession();
    await _silence(_standbyPlayer);
    try {
      await _activePlayer.stop();
    } catch (_) {}
  }

  Future<void> _advanceAfterCompletion() async {
    final before = _queueManager.currentTrack;
    final target = await _queueManager.next(isManual: false);
    if (target == null) {
      await _endOfQueue();
    } else if (identical(target, before)) {
      // Loop.one / single-track Loop.all: the queue asks to repeat.
      await _restartCurrent(play: true);
    } else {
      await _playTarget(target, play: true, crossfade: false);
    }
  }

  // --------------------------------------------------------------------------
  // Transitions
  // --------------------------------------------------------------------------

  /// Aborts the in-flight transition, keeping whichever player is currently
  /// designated as active:
  /// - auto: reverts to the outgoing track (queue was never advanced);
  /// - manual: jumps to the end state (incoming track at full volume).
  ///
  /// The cancellation is synchronous; the returned future completes when the
  /// restore commands (issued in order) have been processed by the players.
  Future<void> _abortTransition() {
    final transition = _transition;
    if (transition == null) return _pendingRestore;
    _transition = null;
    _crossfadeManager.cancel();

    final active = _activePlayer;
    final standby = _standbyPlayer;
    final restore = Future.wait<void>([
      active.setVolume(_masterVolume),
      standby.setVolume(0.0),
      standby.stop(),
    ]).then<void>(
      (_) {},
      onError: (Object e) => debugPrint('[AudioEngine] Restore failed: $e'),
    );
    _pendingRestore = restore;

    // The outgoing track may have ended while the (now aborted) auto
    // crossfade owned the transition; its completion event was ignored, so
    // hand it to the normal completion path.
    if (transition.kind == _TransitionKind.auto && active.isCompleted) {
      _scheduleCompletion(verifyPosition: false);
    }
    return restore;
  }

  Future<void> _abortAutoTransitionIfDisabled() async {
    final enabled =
        _crossfadeConfig.enabled && _crossfadeConfig.duration > Duration.zero;
    if (!enabled && _transition?.kind == _TransitionKind.auto) {
      await _abortTransition();
    }
  }

  /// Reacts to queue candidate changes (synchronous broadcast).
  void _onNextCandidateChanged(QueueItem? candidate) {
    final transition = _transition;
    if (transition == null || transition.kind != _TransitionKind.auto) return;
    if (QueueManager.isSameItem(candidate, transition.target)) return;
    unawaited(_abortTransition());
  }

  /// Turns a running auto crossfade into a committed (manual) one.
  bool _promoteAutoTransition() {
    final transition = _transition;
    if (transition == null ||
        transition.kind != _TransitionKind.auto ||
        !_crossfadeManager.isActive) {
      return false;
    }

    // Flip the kind first so the candidate change emitted by commitNext()
    // is not interpreted as an invalidation.
    transition.kind = _TransitionKind.manual;
    if (_queueManager.commitNext(transition.target) == null) {
      transition.kind = _TransitionKind.auto;
      return false;
    }
    _activePlayer = transition.incoming;
    _standbyPlayer = transition.outgoing;
    _bumpSession();
    _bindActivePlayer();
    _emitState();
    return true;
  }

  void _onCrossEnd(_Transition transition) {
    if (_disposed) return;
    _schedule(() async {
      if (_disposed || !identical(_transition, transition)) return;
      _transition = null;

      if (transition.kind == _TransitionKind.auto) {
        if (_queueManager.commitNext(transition.target) == null) {
          // The queue no longer expects this track (should have been aborted by
          // the candidate stream). Drop it and let the queue decide.
          unawaited(_silence(transition.incoming));
          _scheduleCompletion(verifyPosition: false);
          _emitState();
          return;
        }
        _activePlayer = transition.incoming;
        _standbyPlayer = transition.outgoing;
        _bumpSession();
        _bindActivePlayer();
      }

      if (_activePlayer.isCompleted) {
        _scheduleCompletion(verifyPosition: false);
      }
      _emitState();
    });
  }

  ({QueueItem next, Duration duration})? _planAutoCrossfade(Duration position) {
    if (!_crossfadeConfig.enabled || _crossfadeConfig.duration <= Duration.zero) {
      return null;
    }
    if (!_activePlayer.isPlaying) return null;

    final total = _activePlayer.duration;
    if (total <= Duration.zero) return null;
    final remaining = total - position;
    if (remaining <= Duration.zero) return null;

    // "What comes next" is entirely the queue's decision (Loop.one, end of
    // queue and duplicate paths all yield null).
    final next = _queueManager.peekNext(distinct: true);
    if (next == null || QueueManager.isSameItem(next, _failedAutoTarget)) {
      return null;
    }

    final duration = _clampCrossfadeDuration(
      outgoingDuration: total,
      outgoingRemaining: remaining,
      targetDuration: _crossfadeConfig.duration,
      incomingDuration: next.duration,
    );
    if (duration <= Duration.zero || remaining > duration) return null;
    return (next: next, duration: duration);
  }

  void _maybeScheduleAutoCrossfade(Duration position) {
    if (_disposed || _autoStartScheduled || _transition != null) return;
    if (_planAutoCrossfade(position) == null) return;

    _autoStartScheduled = true;
    _schedule(() async {
      _autoStartScheduled = false;
      if (_transition != null) return;
      // Re-plan: commands may have run between scheduling and execution.
      final plan = _planAutoCrossfade(_activePlayer.position);
      if (plan == null) return;
      await _startAutoCrossfade(plan.next, plan.duration);
    });
  }

  Future<void> _startAutoCrossfade(QueueItem next, Duration plannedDuration) async {
    final outgoing = _activePlayer;
    final incoming = _standbyPlayer;
    final transition = _Transition(
      kind: _TransitionKind.auto,
      target: next,
      outgoing: outgoing,
      incoming: incoming,
    );
    _transition = transition;

    final ok = await _openOn(incoming, next, play: false, volume: 0.0);
    if (!identical(_transition, transition)) return; // aborted while preparing
    if (!ok) {
      _transition = null;
      _failedAutoTarget = next;
      await _silence(incoming);
      return;
    }

    // Preparation took time: never fade longer than what is left.
    final remaining = outgoing.duration - outgoing.position;
    final duration = remaining <= Duration.zero
        ? Duration.zero
        : (remaining < plannedDuration ? remaining : plannedDuration);

    await _crossfadeManager.cross(
      playerOut: outgoing,
      playerIn: incoming,
      targetDuration: duration,
      curve: _crossfadeConfig.curve,
      masterVolume: _masterVolume,
      playbackRate: _playbackRate,
      onCrossEnd: () => _onCrossEnd(transition),
    );
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

  // --------------------------------------------------------------------------
  // Completion Handling
  // --------------------------------------------------------------------------

  void _scheduleCompletion({bool verifyPosition = true}) {
    final session = _playbackSession;
    final player = _activePlayer;
    _schedule(() async {
      if (session != _playbackSession || !identical(player, _activePlayer)) return;
      if (_transition?.kind == _TransitionKind.auto) return;
      if (verifyPosition && !_isAtEnd(player)) return; // stale event
      await _advanceAfterCompletion();
    });
  }

  bool _isAtEnd(AudioPlayerAdapter player) {
    final total = player.duration;
    if (total <= Duration.zero) return true;
    return player.position >= total - _completionTolerance;
  }

  // --------------------------------------------------------------------------
  // Player Helpers
  // --------------------------------------------------------------------------

  /// Opens [item] on [player] paused, at [volume], positioned at zero, and
  /// optionally starts it. Returns false if the file could not be opened.
  Future<bool> _openOn(
    AudioPlayerAdapter player,
    QueueItem item, {
    required bool play,
    required double volume,
  }) async {
    try {
      await player.setVolume(volume);
      await _configurePlayerProperties(player);
      await player.open(item.filePath, play: false);
      await player.seek(Duration.zero);
      if (play) {
        await player.play();
      }
      return true;
    } catch (e) {
      debugPrint('[AudioEngine] Failed to open ${item.filePath}: $e');
      try {
        await player.stop();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _silence(AudioPlayerAdapter player) async {
    try {
      await player.setVolume(0.0);
      await player.stop();
    } catch (_) {}
  }

  Future<void> _configurePlayerProperties(AudioPlayerAdapter player) async {
    try {
      await player.setRate(_playbackRate);
      await player.setPitch(_playbackPitch);
      await player.setEqualizer(_equalizer);
      await player.setSkipSilence(_skipSilence);
      final device = _currentDevice;
      if (device != null) {
        await player.setDevice(device);
      }
    } catch (_) {}
  }

  void _bumpSession() {
    _playbackSession++;
    _failedAutoTarget = null;
  }

  // --------------------------------------------------------------------------
  // Stream & State Management
  // --------------------------------------------------------------------------

  void _bindActivePlayer() {
    for (final sub in _playerSubscriptions) {
      sub.cancel();
    }
    _playerSubscriptions.clear();
    if (_disposed) return;

    final player = _activePlayer;
    bool isCurrent() => !_disposed && identical(player, _activePlayer);

    _playerSubscriptions.add(
      player.positionStream.listen((pos) {
        if (!isCurrent()) return;
        if (!_positionStreamController.isClosed) {
          _positionStreamController.add(pos);
        }
        _maybeEmitPositionState(pos);
        _maybeScheduleAutoCrossfade(pos);
      }),
    );

    _playerSubscriptions.add(
      player.durationStream.listen((dur) {
        if (!isCurrent()) return;
        _stateSubject.add(currentState.copyWith(duration: dur));
      }),
    );

    _playerSubscriptions.add(
      player.playingStream.listen((playing) {
        if (!isCurrent()) return;
        _stateSubject.add(
          currentState.copyWith(
            playing: playing,
            completed: playing ? false : currentState.completed,
          ),
        );
      }),
    );

    _playerSubscriptions.add(
      player.bufferingStream.listen((buffering) {
        if (!isCurrent()) return;
        _stateSubject.add(currentState.copyWith(buffering: buffering));
      }),
    );

    _playerSubscriptions.add(
      player.completedStream.listen((completed) {
        if (!isCurrent()) return;
        if (!completed) {
          if (currentState.completed) {
            _stateSubject.add(currentState.copyWith(completed: false));
          }
          return;
        }
        // During an auto crossfade the outgoing track is expected to end; the
        // crossfade completion commits the transition instead.
        if (_transition?.kind == _TransitionKind.auto) return;
        _scheduleCompletion();
      }),
    );
  }

  void _maybeEmitPositionState(Duration position) {
    final last = _lastStateEmit;
    final now = DateTime.now();
    final jumped = (position - currentState.position).abs() > const Duration(milliseconds: 1500);
    if (!jumped && last != null && now.difference(last) < _positionStateInterval) {
      return;
    }
    _lastStateEmit = now;
    _stateSubject.add(currentState.copyWith(position: position));
  }

  void _emitState() {
    if (_stateSubject.isClosed) return;
    final previous = currentState;
    final active = _activePlayer;
    _lastStateEmit = DateTime.now();
    // Built from scratch (not copyWith) so nullable fields such as
    // mixOffset can be cleared.
    _stateSubject.add(
      PlaybackState(
        index: math.max(0, _queueManager.currentIndex),
        playables: _queueManager.activeQueue,
        mixOffset: _queueManager.mixOffset,
        playing: active.isPlaying,
        buffering: active.isBuffering,
        completed: _queueEnded || (!active.isPlaying && active.isCompleted),
        position: active.position,
        duration: active.duration,
        rate: _playbackRate,
        pitch: _playbackPitch,
        volume: _masterVolume,
        shuffle: _queueManager.isShuffled,
        loop: _queueManager.loopMode,
        crossfadeDuration: _crossfadeConfig.duration,
        skipSilence: _skipSilence,
        audioBitrate: previous.audioBitrate,
        audioSampleRate: previous.audioSampleRate,
        audioChannels: previous.audioChannels,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Cleanup
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _transition = null;
    _crossfadeManager.dispose();

    await _queueSubscription?.cancel();
    _queueSubscription = null;
    for (final sub in _playerSubscriptions) {
      await sub.cancel();
    }
    _playerSubscriptions.clear();

    if (_ownsQueueManager) {
      _queueManager.dispose();
    }

    await _playerA.dispose();
    await _playerB.dispose();
    await _positionStreamController.close();
    await _stateSubject.close();
  }
}
