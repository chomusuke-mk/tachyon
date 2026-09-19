import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/audio_engine_service.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

class PlaybackController extends ChangeNotifier {
  final AudioEngineService _audioEngine;
  final AppDatabase _database;
  final SettingsRepository _settingsRepository;

  late StreamSubscription<PlaybackState> _engineSubscription;
  PlaybackState _state = const PlaybackState.initial();

  // History and persistence tracking
  bool _isDisposed = false;
  String? _currentlyLoggedHistoryUri;
  bool _historyLoggedForCurrentTrack = false;

  PlaybackController({
    required AudioEngineService audioEngineService,
    required this._database,
    required this._settingsRepository,
  }) : _audioEngine = audioEngineService {
    _state = _audioEngine.currentState;
    _engineSubscription = _audioEngine.stateStream.listen((newState) {
      _state = newState;
      _checkHistoryLogging(newState);
      _checkStatePersistence(newState);
      notifyListeners();
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

  Duration get position => _state.position;
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
  bool get exclusiveAudio => _state.exclusiveAudio;
  ReplayGainMode get replayGain => _state.replayGain;
  double get replayGainPreamp => _state.replayGainPreamp;

  // ---------------------------------------------------------------------------
  // High-Level Track Selection & Queue Actions
  // ---------------------------------------------------------------------------
  Future<void> playTrack(Track track, {List<Track>? contextTracks}) async {
    final trackList = (contextTracks != null && contextTracks.isNotEmpty)
        ? contextTracks
        : [track];

    final queueItems = trackList.map((t) => QueueItem.fromTrack(t)).toList();
    var startIndex = queueItems.indexWhere((q) => q.uri == track.uri);
    if (startIndex == -1) startIndex = 0;

    await _audioEngine.open(
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

    await _audioEngine.open(
      queueItems,
      index: startIndex,
      play: true,
      shuffle: shuffle,
    );
  }

  Future<void> playNext(Track track) async {
    final item = QueueItem.fromTrack(track);
    await _audioEngine.insertNext(item);
  }

  Future<void> addToQueue(Track track) async {
    final item = QueueItem.fromTrack(track);
    await _audioEngine.append([item]);
  }

  Future<void> appendTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final items = tracks.map((t) => QueueItem.fromTrack(t)).toList();
    await _audioEngine.append(items);
  }

  Future<void> removeFromQueue(int index) async {
    await _audioEngine.remove(index);
  }

  Future<void> reorderQueue(int from, int to) async {
    await _audioEngine.reorder(from, to);
  }

  Future<void> clearQueue() async {
    await _audioEngine.open([]);
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    await _audioEngine.open(_state.playables, index: index, play: true);
  }

  Future<void> playTrackAtIndex(int index) => skipToQueueIndex(index);

  bool get isInfiniteMixEnabled {
    final engine = _audioEngine;
    return engine.queueManager.infiniteMixEnabled;
  }

  void setInfiniteMix(bool enabled) {
    final engine = _audioEngine;
    engine.queueManager.setInfiniteMix(enabled);
    notifyListeners();
  }

  void toggleInfiniteMix() {
    setInfiniteMix(!isInfiniteMixEnabled);
  }

  // ---------------------------------------------------------------------------
  // Transport Controls
  // ---------------------------------------------------------------------------
  Future<void> play() => _audioEngine.play();
  Future<void> pause() => _audioEngine.pause();

  Future<void> playOrPause() async {
    if (_state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() => _audioEngine.stop();
  Future<void> next() => _audioEngine.next();
  Future<void> previous() => _audioEngine.previous();
  Future<void> seek(Duration pos) => _audioEngine.seek(pos);

  Future<void> setVolume(double vol) => _audioEngine.setVolume(vol);
  Future<void> setRate(double rate) => _audioEngine.setRate(rate);
  Future<void> setPitch(double pitch) => _audioEngine.setPitch(pitch);

  Future<void> toggleShuffle() => _audioEngine.toggleShuffle();
  Future<void> setLoopMode(Loop loop) => _audioEngine.setLoopMode(loop);

  Future<void> toggleLoopMode() async {
    final nextMode = _state.loop.next();
    await _audioEngine.setLoopMode(nextMode);
  }

  Future<void> cycleLoopMode() => toggleLoopMode();

  Future<void> setCrossfadeConfig(CrossfadeConfig config) =>
      _audioEngine.setCrossfadeConfig(config);

  Future<void> setReplayGain(ReplayGainMode mode) =>
      _audioEngine.setReplayGain(mode);
  Future<void> setReplayGainPreamp(double preamp) =>
      _audioEngine.setReplayGainPreamp(preamp);
  Future<void> setExclusiveAudio(bool exclusive) =>
      _audioEngine.setExclusiveAudio(exclusive);

  // ---------------------------------------------------------------------------
  // History Logging & State Persistence Helpers
  // ---------------------------------------------------------------------------
  void _checkHistoryLogging(PlaybackState newState) {
    final currentUri = newState.currentTrack?.uri;
    if (currentUri != _currentlyLoggedHistoryUri) {
      _currentlyLoggedHistoryUri = currentUri;
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
          _database.addTrackToPlaylist(AppDatabase.historyPlaylistId, trackId);
        }
      }
    }
  }

  void _checkStatePersistence(PlaybackState newState) {
    final current = newState.currentTrack;
    if (current != null) {
      _settingsRepository.setLastPlayed(
        uri: current.uri,
        positionMs: newState.position.inMilliseconds,
      );
    }
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
    super.dispose();
  }
}
