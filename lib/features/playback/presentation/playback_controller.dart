import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, Equalizer;

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

class PlaybackController extends ChangeNotifier {
  final TachyonBackendClient _backend;
  final SettingsRepository _settingsRepository;

  late StreamSubscription<PlaybackState> _engineSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  PlaybackState _state = const PlaybackState.initial();

  Equalizer _equalizer = Equalizer.flat;
  AudioDevice? _currentDevice;
  bool _isInfiniteMixEnabled = false;

  // Scoped high-frequency position notifier
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  // Persistence throttling state
  DateTime? _lastPersistenceTime;
  String? _lastPersistedFilePath;
  int? _lastPersistedPositionMs;
  static const Duration _persistenceThrottle = Duration(seconds: 5);

  @visibleForTesting
  String? get lastPersistedFilePath => _lastPersistedFilePath;
  @visibleForTesting
  int? get lastPersistedPositionMs => _lastPersistedPositionMs;

  // History and persistence tracking
  bool _isDisposed = false;
  String? _currentlyLoggedHistoryFilePath;
  bool _historyLoggedForCurrentTrack = false;

  PlaybackController({
    required this._backend,
    required this._settingsRepository,
  }) {
    _backend.getPlaybackState().then((s) {
      if (!_isDisposed) {
        _state = s;
        _positionNotifier.value = s.position;
        notifyListeners();
      }
    });

    _engineSubscription = _backend.playbackStateStream.listen((newState) {
      final oldState = _state;
      _state = newState;

      // 1. Update high-frequency position notifier
      if (_positionNotifier.value != newState.position) {
        _positionNotifier.value = newState.position;
      }

      // 2. Perform background checks
      _checkHistoryLogging(newState);
      _checkStatePersistence(oldState, newState);

      // 3. Notify listeners ONLY on discrete state changes
      if (_hasDiscreteStateChanged(oldState, newState)) {
        notifyListeners();
      }
    });

    _positionSubscription = _backend.positionStream.listen((pos) {
      if (_positionNotifier.value != pos) {
        _positionNotifier.value = pos;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Reactive Getters (Exposed for MiniPlayer, NowPlaying, TransportBar)
  // ---------------------------------------------------------------------------
  PlaybackState get state => _state;
  QueueItem? get currentTrack => _state.currentTrack;
  bool get isPlaying => _state.playing;
  bool get isBuffering => _state.buffering;
  bool get isCompleted => _state.completed;

  Duration get position => _positionNotifier.value;
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueListenable<Duration> get positionListenable => _positionNotifier;
  Duration get duration => _state.duration;
  double get progress => _state.progress;
  Duration get remaining => _state.remaining;

  double get volume => _state.volume;
  double get rate => _state.rate;
  double get pitch => _state.pitch;

  Loop get loopMode => _state.loop;
  bool get isShuffled => _state.shuffle;

  List<QueueItem> get queue => _state.playables;
  int get currentIndex => _state.index;

  bool get hasNext => _state.hasNext;
  bool get hasPrevious => _state.hasPrevious;

  CrossfadeConfig get crossfadeConfig => _state.crossfadeConfig;
  bool get skipSilence => _state.skipSilence;
  // ---------------------------------------------------------------------------
  // High-Level Track Selection & Queue Actions
  // ---------------------------------------------------------------------------
  Future<void> playTrack(Track track, {List<Track>? contextTracks}) async {
    final trackList = (contextTracks != null && contextTracks.isNotEmpty)
        ? contextTracks
        : [track];

    final queueItems = trackList.map((t) => QueueItem.fromTrack(t)).toList();
    var startIndex = queueItems.indexWhere((q) => q.filePath == track.filePath);
    if (startIndex == -1) startIndex = 0;

    await _backend.open(
      queueItems,
      index: startIndex,
      play: true,
      shuffle: _state.shuffle,
    );
  }

  Future<void> playAll(
    List<Track> tracks, {
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final queueItems = tracks.map((t) => QueueItem.fromTrack(t)).toList();

    await _backend.open(
      queueItems,
      index: startIndex,
      play: true,
      shuffle: shuffle,
    );
  }

  Future<void> playNext(Track track) async {
    final item = QueueItem.fromTrack(track);
    await _backend.insertNext(item);
  }

  Future<void> addToQueue(Track track) async {
    final item = QueueItem.fromTrack(track);
    await _backend.append([item]);
  }

  Future<void> appendTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final items = tracks.map((t) => QueueItem.fromTrack(t)).toList();
    await _backend.append(items);
  }

  Future<void> removeFromQueue(int index) async {
    await _backend.removeQueueItem(index);
  }

  Future<void> reorderQueue(int from, int to) async {
    await _backend.reorderQueue(from, to);
  }

  Future<void> clearQueue() async {
    await _backend.clearQueue();
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    await _backend.skipToIndex(index);
  }

  Future<void> playTrackAtIndex(int index) => skipToQueueIndex(index);

  Equalizer get equalizer => _equalizer;
  AudioDevice? get currentDevice => _currentDevice;

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    await _backend.setEqualizer(equalizer);
    notifyListeners();
  }

  Future<List<AudioDevice>> getAudioDevices() => _backend.getAudioDevices();

  Future<bool> setAudioDevice(AudioDevice device) async {
    _currentDevice = device;
    await _backend.setOutputDevice(device);
    notifyListeners();
    return true;
  }

  bool get isInfiniteMixEnabled => _isInfiniteMixEnabled;

  void setInfiniteMix(bool enabled) {
    _isInfiniteMixEnabled = enabled;
    _backend.setInfiniteMix(enabled);
    notifyListeners();
  }

  void toggleInfiniteMix() {
    setInfiniteMix(!isInfiniteMixEnabled);
  }

  // ---------------------------------------------------------------------------
  // Transport Controls
  // ---------------------------------------------------------------------------
  Future<void> play() => _backend.play();
  Future<void> pause() => _backend.pause();

  Future<void> playOrPause() async {
    if (_state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() => _backend.stop();
  Future<void> next() => _backend.next();
  Future<void> previous() => _backend.previous();
  Future<void> seek(Duration pos) => _backend.seek(pos);

  Future<void> setVolume(double vol) => _backend.setVolume(vol);
  Future<void> setRate(double rate) => _backend.setRate(rate);
  Future<void> setPitch(double pitch) => _backend.setPitch(pitch);

  Future<void> toggleShuffle() => _backend.setShuffle(!_state.shuffle);
  Future<void> setLoopMode(Loop loop) => _backend.setLoopMode(loop);

  Future<void> toggleLoopMode() async {
    final nextMode = _state.loop.next();
    await _backend.setLoopMode(nextMode);
  }

  Future<void> cycleLoopMode() => toggleLoopMode();

  Future<void> setCrossfadeConfig(CrossfadeConfig config) =>
      _backend.setCrossfadeConfig(config);

  Future<void> setSkipSilence(bool enabled) => _backend.setSkipSilence(enabled);

  // ---------------------------------------------------------------------------
  // History Logging & State Persistence Helpers
  // ---------------------------------------------------------------------------
  void _checkHistoryLogging(PlaybackState newState) {
    final currentFilePath = newState.currentTrack?.filePath;
    if (currentFilePath != _currentlyLoggedHistoryFilePath) {
      _currentlyLoggedHistoryFilePath = currentFilePath;
      _historyLoggedForCurrentTrack = false;
    }

    // Log to History if track has played > 15s or reached 50%
    if (!_historyLoggedForCurrentTrack && newState.currentTrack != null) {
      final hasPlayedThreshold =
          newState.position.inSeconds > 15 ||
          (newState.duration.inMilliseconds > 0 && newState.progress >= 0.5);

      if (hasPlayedThreshold) {
        _historyLoggedForCurrentTrack = true;
        final trackId = newState.currentTrack!.trackId;
        if (trackId != null) {
          _backend.addTracksToPlaylist(AppDatabase.historyPlaylistId, [
            trackId,
          ]);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Discrete State Change Detection
  // ---------------------------------------------------------------------------
  bool _hasDiscreteStateChanged(PlaybackState prev, PlaybackState next) {
    return prev.index != next.index ||
        prev.playing != next.playing ||
        prev.buffering != next.buffering ||
        prev.completed != next.completed ||
        prev.duration != next.duration ||
        prev.rate != next.rate ||
        prev.pitch != next.pitch ||
        prev.volume != next.volume ||
        prev.shuffle != next.shuffle ||
        prev.loop != next.loop ||
        prev.crossfadeDuration != next.crossfadeDuration ||
        prev.skipSilence != next.skipSilence ||
        prev.audioBitrate != next.audioBitrate ||
        prev.audioSampleRate != next.audioSampleRate ||
        prev.audioChannels != next.audioChannels ||
        prev.mixOffset != next.mixOffset ||
        prev.hasPrevious != next.hasPrevious ||
        prev.currentTrack?.filePath != next.currentTrack?.filePath ||
        !listEquals(prev.playables, next.playables);
  }

  // ---------------------------------------------------------------------------
  // Throttled State Persistence
  // ---------------------------------------------------------------------------
  void _checkStatePersistence(PlaybackState oldState, PlaybackState newState) {
    final current = newState.currentTrack;
    if (current == null) return;

    final isTrackTransition =
        oldState.currentTrack?.filePath != current.filePath;
    final isPauseTransition = oldState.playing && !newState.playing;
    final isSeekTransition =
        (newState.position - oldState.position).abs() >
        const Duration(seconds: 2);
    final isStopOrCompleted = oldState.playing && newState.completed;

    final shouldForceWrite =
        isTrackTransition ||
        isPauseTransition ||
        isSeekTransition ||
        isStopOrCompleted;

    if (shouldForceWrite) {
      _flushStatePersistence(
        current.filePath,
        newState.position.inMilliseconds,
      );
      return;
    }

    // Continuous playback throttling: flush once every 5 seconds
    if (newState.playing) {
      final now = DateTime.now();
      if (_lastPersistenceTime == null ||
          now.difference(_lastPersistenceTime!) >= _persistenceThrottle) {
        _flushStatePersistence(
          current.filePath,
          newState.position.inMilliseconds,
        );
      }
    }
  }

  Future<void> flushStatePersistence() async {
    final current = _state.currentTrack;
    if (current != null) {
      await _flushStatePersistence(
        current.filePath,
        _positionNotifier.value.inMilliseconds,
      );
    }
  }

  Future<void> _flushStatePersistence(String filePath, int positionMs) async {
    _lastPersistenceTime = DateTime.now();
    _lastPersistedFilePath = filePath;
    _lastPersistedPositionMs = positionMs;

    await _settingsRepository.setLastPlayed(
      filePath: filePath,
      positionMs: positionMs,
    );
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _engineSubscription.cancel();
    _positionSubscription?.cancel();
    if (_state.currentTrack != null) {
      _settingsRepository.setLastPlayed(
        filePath: _state.currentTrack!.filePath,
        positionMs: _positionNotifier.value.inMilliseconds,
      );
    }
    _positionNotifier.dispose();
    super.dispose();
  }
}
