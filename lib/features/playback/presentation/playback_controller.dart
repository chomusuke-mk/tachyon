// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, Equalizer;

import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/data/library_store.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';

export 'package:tachyon/features/playback/domain/loop_mode.dart';

class PlaybackController extends ChangeNotifier {
  final TachyonBackendClient _backend;
  final SettingsRepository _settingsRepository;
  final LibraryStore Function()? _libraryStoreSupplier;

  late StreamSubscription<PlaybackState> _engineSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<void>? _catalogSubscription;
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
    required TachyonBackendClient backend,
    required SettingsRepository settingsRepository,
    LibraryStore Function()? libraryStoreSupplier,
  }) : _backend = backend,
       _settingsRepository = settingsRepository,
       _libraryStoreSupplier = libraryStoreSupplier {
    _backend.getPlaybackState().then((s) {
      if (!_isDisposed) {
        _state = _resolveStateTracks(s);
        _positionNotifier.value = _state.position;
        notifyListeners();
      }
    }).catchError((e) {
      debugPrint('[PlaybackController] Error getting initial playback state: $e');
    });

    _engineSubscription = _backend.playbackStateStream.listen((newState) {
      final oldState = _state;
      final resolvedState = _resolveStateTracks(newState);
      _state = resolvedState;

      // 1. Update high-frequency position notifier
      if (_positionNotifier.value != resolvedState.position) {
        _positionNotifier.value = resolvedState.position;
      }

      // 2. Perform background checks
      _checkHistoryLogging(resolvedState);
      _checkStatePersistence(oldState, resolvedState);

      // 3. Notify listeners ONLY on discrete state changes
      if (_hasDiscreteStateChanged(oldState, resolvedState)) {
        notifyListeners();
      }
    });

    _catalogSubscription = _backend.catalogUpdatedStream.listen((_) {
      if (!_isDisposed) {
        _state = _resolveStateTracks(_state);
        notifyListeners();
      }
    });

    _positionSubscription = _backend.positionStream.listen((pos) {
      if (_positionNotifier.value != pos) {
        _positionNotifier.value = pos;
      }
    });
  }

  PlaybackState _resolveStateTracks(PlaybackState raw) {
    final store = _libraryStoreSupplier?.call();
    if (store == null || raw.playables.isEmpty) return raw;

    final resolvedPlayables = raw.playables.map((item) {
      final t = item.track;
      if (t == null) return item;
      final resolved =
          (t.id != null ? store.getTrackById(t.id!) : null) ??
          store.getTrackByPath(t.filePath);
      if (resolved != null && !identical(resolved, t)) {
        return item.copyWith(track: resolved);
      }
      return item;
    }).toList();

    return raw.copyWith(playables: resolvedPlayables);
  }

  // ---------------------------------------------------------------------------
  // Reactive Getters (Exposed for MiniPlayer, NowPlaying, TransportBar)
  // ---------------------------------------------------------------------------
  PlaybackState get state => _state;
  PlaylistEntry? get currentEntry => _state.currentEntry;
  Track? get currentTrack => _state.currentTrack;
  bool isCurrentTrack(Track? track) =>
      track != null &&
      (_state.currentTrack == track ||
          (_state.currentTrack?.id != null &&
              _state.currentTrack?.id == track.id) ||
          (_state.currentTrack?.filePath.isNotEmpty == true &&
              _state.currentTrack?.filePath == track.filePath));
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

  List<PlaylistEntry> get queue => _state.playables;
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

    final trackIds = trackList.map((t) => t.id).whereType<int>().toList();
    var startIndex = trackList.indexWhere((t) => t.filePath == track.filePath);
    if (startIndex == -1) startIndex = 0;

    try {
      if (trackIds.length == trackList.length && trackIds.isNotEmpty) {
        await _backend.playQueue(
          trackIds,
          startIndex: startIndex,
          play: true,
          shuffle: _state.shuffle,
        );
      } else if (track.id != null) {
        await _backend.playTrack(track.id!, play: true);
      }
    } catch (e) {
      debugPrint('[PlaybackController] Error in playTrack: $e');
    }
  }

  Future<void> playAll(
    List<Track> tracks, {
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    try {
      final trackIds = tracks.map((t) => t.id).whereType<int>().toList();
      if (trackIds.length == tracks.length && trackIds.isNotEmpty) {
        await _backend.playQueue(
          trackIds,
          startIndex: startIndex,
          play: true,
          shuffle: shuffle,
        );
      }
    } catch (e) {
      debugPrint('[PlaybackController] Error in playAll: $e');
    }
  }

  Future<void> playNext(Track track) async {
    if (track.id != null) {
      try {
        await _backend.insertNext(track.id!);
      } catch (e) {
        debugPrint('[PlaybackController] Error in playNext: $e');
      }
    }
  }

  Future<void> addToQueue(Track track) async {
    if (track.id != null) {
      try {
        await _backend.append([track.id!]);
      } catch (e) {
        debugPrint('[PlaybackController] Error in addToQueue: $e');
      }
    }
  }

  Future<void> appendTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    try {
      final trackIds = tracks.map((t) => t.id).whereType<int>().toList();
      if (trackIds.isNotEmpty) {
        await _backend.append(trackIds);
      }
    } catch (e) {
      debugPrint('[PlaybackController] Error in appendTracks: $e');
    }
  }

  Future<void> removeFromQueue(int index) async {
    try {
      await _backend.removeQueueItem(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in removeFromQueue: $e');
    }
  }

  Future<void> reorderQueue(int from, int to) async {
    try {
      await _backend.reorderQueue(from, to);
    } catch (e) {
      debugPrint('[PlaybackController] Error in reorderQueue: $e');
    }
  }

  Future<void> clearQueue() async {
    try {
      await _backend.clearQueue();
    } catch (e) {
      debugPrint('[PlaybackController] Error in clearQueue: $e');
    }
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    try {
      await _backend.skipToIndex(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in skipToQueueIndex: $e');
    }
  }

  Future<void> playTrackAtIndex(int index) => skipToQueueIndex(index);

  Equalizer get equalizer => _equalizer;
  AudioDevice? get currentDevice => _currentDevice;

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    try {
      await _backend.setEqualizer(equalizer);
    } catch (e) {
      debugPrint('[PlaybackController] setEqualizer error: $e');
    }
    notifyListeners();
  }

  Future<List<AudioDevice>> getAudioDevices() async {
    try {
      return await _backend.getAudioDevices();
    } catch (e) {
      debugPrint('[PlaybackController] getAudioDevices error: $e');
      return const [];
    }
  }

  Future<bool> setAudioDevice(AudioDevice device) async {
    _currentDevice = device;
    try {
      await _backend.setOutputDevice(device);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[PlaybackController] setAudioDevice error: $e');
      notifyListeners();
      return false;
    }
  }

  bool get isInfiniteMixEnabled => _isInfiniteMixEnabled;

  void setInfiniteMix(bool enabled) {
    _isInfiniteMixEnabled = enabled;
    try {
      _backend.setInfiniteMix(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setInfiniteMix error: $e');
    }
    notifyListeners();
  }

  void toggleInfiniteMix() {
    setInfiniteMix(!isInfiniteMixEnabled);
  }

  // ---------------------------------------------------------------------------
  // Transport Controls
  // ---------------------------------------------------------------------------
  Future<void> play() async {
    try {
      await _backend.play();
    } catch (e) {
      debugPrint('[PlaybackController] play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _backend.pause();
    } catch (e) {
      debugPrint('[PlaybackController] pause error: $e');
    }
  }

  Future<void> playOrPause() async {
    if (_state.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    try {
      await _backend.stop();
    } catch (e) {
      debugPrint('[PlaybackController] stop error: $e');
    }
  }

  Future<void> next() async {
    try {
      await _backend.next();
    } catch (e) {
      debugPrint('[PlaybackController] next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await _backend.previous();
    } catch (e) {
      debugPrint('[PlaybackController] previous error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _backend.seek(pos);
    } catch (e) {
      debugPrint('[PlaybackController] seek error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    try {
      await _backend.setVolume(vol);
    } catch (e) {
      debugPrint('[PlaybackController] setVolume error: $e');
    }
  }

  Future<void> setRate(double rate) async {
    try {
      await _backend.setRate(rate);
    } catch (e) {
      debugPrint('[PlaybackController] setRate error: $e');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _backend.setPitch(pitch);
    } catch (e) {
      debugPrint('[PlaybackController] setPitch error: $e');
    }
  }

  Future<void> toggleShuffle() async {
    try {
      await _backend.setShuffle(!_state.shuffle);
    } catch (e) {
      debugPrint('[PlaybackController] toggleShuffle error: $e');
    }
  }

  Future<void> setLoopMode(Loop loop) async {
    try {
      await _backend.setLoopMode(loop);
    } catch (e) {
      debugPrint('[PlaybackController] setLoopMode error: $e');
    }
  }

  Future<void> toggleLoopMode() async {
    try {
      final nextMode = _state.loop.next();
      await _backend.setLoopMode(nextMode);
    } catch (e) {
      debugPrint('[PlaybackController] toggleLoopMode error: $e');
    }
  }

  Future<void> cycleLoopMode() => toggleLoopMode();

  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    try {
      await _backend.setCrossfadeConfig(config);
    } catch (e) {
      debugPrint('[PlaybackController] setCrossfadeConfig error: $e');
    }
  }

  Future<void> setSkipSilence(bool enabled) async {
    try {
      await _backend.setSkipSilence(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setSkipSilence error: $e');
    }
  }

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
        final trackId = newState.currentTrack!.id;
        if (trackId != null) {
          _backend.addTracksToPlaylist(AppDatabase.historyPlaylistId, [
            trackId,
          ]).catchError((e) {
            debugPrint(
              '[PlaybackController] Failed to add track $trackId to history: $e',
            );
          });
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
    _catalogSubscription?.cancel();
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
