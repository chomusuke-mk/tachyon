// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, CrossfeedMode, Equalizer, Reverb;

import 'package:tachyon/core/database/app_database.dart' show AppDatabase;
import 'package:tachyon/core/playback/domain/crossfade_config.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/legacy/audio_engine_service.dart';
import 'package:tachyon/core/playback/legacy/queue_manager.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

export 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, CrossfeedMode, Equalizer, Reverb;
export 'package:tachyon/core/playback/domain/loop_mode.dart';

class PlaybackController extends ChangeNotifier {
  final LibraryStore? _store;
  final SettingsRepository _settingsRepository;
  final AudioEngineService _audioEngine;
  final bool _ownsAudioEngine;

  late StreamSubscription<PlaybackState> _engineSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<dynamic>? _visualizerSubscription;
  StreamSubscription<List<AudioDevice>>? _devicesSubscription;
  PlaybackState _state = const PlaybackState.initial();

  Equalizer _equalizer = Equalizer.flat;
  AudioDevice? _currentDevice;
  List<AudioDevice> _audioDevices = const [];
  bool _isInfiniteMixEnabled = false;
  bool _isMinimized = false;
  int _lastPositionEmitTimestamp = 0;
  int _lastEmittedPositionMs = -1;

  // Scoped high-frequency position notifier
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<List<double>> _visualizerNotifier =
      ValueNotifier<List<double>>(List<double>.filled(14, 0.0));

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
    LibraryStore? store,
    required SettingsRepository settingsRepository,
    AudioEngineService? audioEngine,
  }) : _store = store,
       _settingsRepository = settingsRepository,
       _ownsAudioEngine = audioEngine == null,
       _audioEngine =
           audioEngine ??
           AudioEngineService(
             queueManager: QueueManager(
               libraryTrackProvider: (count) =>
                   store?.getRandomTracks(count) ?? const <Track>[],
             ),
           ) {
    _audioEngine.setVisualizerEnabled(false);
    _state = _audioEngine.state;
    _isInfiniteMixEnabled = _state.isInfiniteMixEnabled;
    _positionNotifier.value = _state.position;

    _engineSubscription = _audioEngine.stateStream.listen((newState) {
      final oldState = _state;
      _state = newState;
      _isInfiniteMixEnabled = newState.isInfiniteMixEnabled;

      if (_positionNotifier.value != newState.position) {
        _positionNotifier.value = newState.position;
      }

      _checkHistoryLogging(newState);
      _checkStatePersistence(oldState, newState);

      if (_hasDiscreteStateChanged(oldState, newState)) {
        notifyListeners();
      }
    });

    _positionSubscription = _audioEngine.positionStream.listen((pos) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final deltaMs = now - _lastPositionEmitTimestamp;
      final minIntervalMs = _isMinimized ? 5000 : 40;
      final jumpThresholdMs = _isMinimized ? 2000 : 1000;
      if (deltaMs < minIntervalMs &&
          (pos.inMilliseconds - _lastEmittedPositionMs).abs() <=
              jumpThresholdMs) {
        return;
      }
      _lastPositionEmitTimestamp = now;
      _lastEmittedPositionMs = pos.inMilliseconds;

      if (_positionNotifier.value != pos) {
        _positionNotifier.value = pos;
      }
      if ((pos.inMilliseconds - _state.position.inMilliseconds).abs() >= 1000) {
        final oldState = _state;
        _state = _state.copyWith(position: pos);
        _checkHistoryLogging(_state);
        _checkStatePersistence(oldState, _state);
      }
    });

    _visualizerSubscription = _audioEngine.visualizerStream.listen((vis) {
      if (!_visualizerEnabled || _isMinimized) return;
      _visualizerNotifier.value = <double>[
        vis.rms,
        vis.peak,
        vis.left,
        vis.right,
        ...vis.bands,
      ];
    });

    _devicesSubscription = _audioEngine.devicesStream.listen((devices) {
      if (!_isDisposed) {
        _audioDevices = devices;
        _applySavedDeviceIfAvailable(devices);
        notifyListeners();
      }
    });

    final savedDeviceId =
        _settingsRepository.getSettings().audioOutputDeviceId;
    if (kIsWeb ||
        !Platform.isAndroid ||
        (savedDeviceId != null && savedDeviceId.isNotEmpty)) {
      _audioEngine.getAudioDevices().then((devices) {
        if (!_isDisposed && devices.isNotEmpty) {
          _audioDevices = devices;
          _applySavedDeviceIfAvailable(devices);
          notifyListeners();
        }
      }).catchError((e) {
        debugPrint(
          '[PlaybackController] Error getting initial audio devices: $e',
        );
      });
    }
  }

  AudioEngineService get audioEngine => _audioEngine;
  QueueManager get queueManager => _audioEngine.queueManager;

  Track _canonicalTrack(Track track) {
    final store = _store;
    if (store == null) return track;
    if (track.id != null) {
      final byId = store.getTrackById(track.id!);
      if (byId != null) return byId;
    }
    return store.getTrackByPath(track.filePath) ?? track;
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

  ValueNotifier<List<double>> get visualizerNotifier => _visualizerNotifier;
  ValueListenable<List<double>> get visualizerListenable => _visualizerNotifier;

  bool _visualizerEnabled = false;

  void setVisualizerEnabled(bool enabled) {
    _visualizerEnabled = enabled;
    if (!enabled) {
      scheduleMicrotask(() {
        if (!_visualizerEnabled && !_isDisposed) {
          _visualizerNotifier.value = const [];
        }
      });
    }
    _audioEngine.setVisualizerEnabled(enabled && !_isMinimized);
  }

  void setMinimized(bool minimized) {
    if (_isMinimized == minimized) return;
    _isMinimized = minimized;
    if (minimized) {
      _audioEngine.setVisualizerEnabled(false);
    } else {
      if (_visualizerEnabled) {
        _audioEngine.setVisualizerEnabled(true);
      }
      final livePos = _audioEngine.state.position;
      _lastPositionEmitTimestamp = DateTime.now().millisecondsSinceEpoch;
      _lastEmittedPositionMs = livePos.inMilliseconds;
      if (_positionNotifier.value != livePos) {
        _positionNotifier.value = livePos;
      }
    }
  }

  Duration get duration => _state.duration;
  double get progress => _state.progress;
  Duration get remaining => _state.remaining;

  double get currentVisualAmplitude => isPlaying
      ? (currentTrack?.getPointAtPosition(position, duration) ?? 0.0)
      : 0.0;

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
  bool get volumeNormalization => _state.volumeNormalization;
  double get preampDb => _state.preampDb;
  double get balance => _state.balance;
  double get spatializerWidth => _state.spatializerWidth;
  bool get mono => _state.mono;
  CrossfeedMode get crossfeedMode => _state.crossfeedMode;
  bool get limiterEnabled => _state.limiterEnabled;
  Reverb get reverb => _audioEngine.reverb;

  // ---------------------------------------------------------------------------
  // High-Level Track Selection & Queue Actions
  // ---------------------------------------------------------------------------
  Future<void> openTracks(
    List<Track> tracks, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    final entries = [
      for (int i = 0; i < tracks.length; i++)
        PlaylistEntry.forQueue(
          id: i,
          position: i,
          track: _canonicalTrack(tracks[i]),
        ),
    ];
    await _audioEngine.open(
      entries,
      index: startIndex,
      play: play,
      shuffle: shuffle,
    );
  }

  Future<void> playTrack(Track track, {List<Track>? contextTracks}) async {
    final trackList = (contextTracks != null && contextTracks.isNotEmpty)
        ? contextTracks
        : [track];

    var startIndex = trackList.indexWhere((t) => t.filePath == track.filePath);
    if (startIndex == -1) startIndex = 0;

    try {
      await openTracks(
        trackList,
        startIndex: startIndex,
        play: true,
        shuffle: _state.shuffle,
      );
    } catch (e) {
      debugPrint('[PlaybackController] Error in playTrack: $e');
    }
  }

  Future<void> playAll(
    List<Track> tracks, {
    bool shuffle = false,
    int? startIndex,
  }) async {
    if (tracks.isEmpty) return;
    try {
      await openTracks(
        tracks,
        startIndex: startIndex,
        play: true,
        shuffle: shuffle,
      );
    } catch (e) {
      debugPrint('[PlaybackController] Error in playAll: $e');
    }
  }

  Future<void> playNext(Track track) async {
    try {
      final entry = PlaylistEntry.forQueue(
        id: 0,
        position: 0,
        track: _canonicalTrack(track),
      );
      await _audioEngine.insertNext(entry);
    } catch (e) {
      debugPrint('[PlaybackController] Error in playNext: $e');
    }
  }

  Future<void> addToQueue(Track track) async {
    await appendTracks([track]);
  }

  Future<void> appendTracks(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    try {
      final entries = [
        for (int i = 0; i < tracks.length; i++)
          PlaylistEntry.forQueue(
            id: i,
            position: i,
            track: _canonicalTrack(tracks[i]),
          ),
      ];
      await _audioEngine.append(entries);
    } catch (e) {
      debugPrint('[PlaybackController] Error in appendTracks: $e');
    }
  }

  Future<void> removeFromQueue(int index) async {
    try {
      await _audioEngine.remove(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in removeFromQueue: $e');
    }
  }

  Future<void> reorderQueue(int from, int to) async {
    try {
      await _audioEngine.reorder(from, to);
    } catch (e) {
      debugPrint('[PlaybackController] Error in reorderQueue: $e');
    }
  }

  Future<void> clearQueue() async {
    try {
      await _audioEngine.clearQueue();
    } catch (e) {
      debugPrint('[PlaybackController] Error in clearQueue: $e');
    }
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= _state.queue.length) return;
    try {
      await _audioEngine.skipToIndex(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in skipToQueueIndex: $e');
    }
  }

  Future<void> playTrackAtIndex(int index) => skipToQueueIndex(index);

  Equalizer get equalizer => _equalizer;
  AudioDevice? get currentDevice => _currentDevice;
  List<AudioDevice> get audioDevices => _audioDevices;
  Stream<List<AudioDevice>> get devicesStream => _audioEngine.devicesStream;

  void _applySavedDeviceIfAvailable(List<AudioDevice> devices) {
    final savedId = _settingsRepository.getSettings().audioOutputDeviceId;
    if (savedId != null && savedId.isNotEmpty && _currentDevice == null) {
      final match = devices.where((d) => d.id == savedId).firstOrNull;
      if (match != null) {
        setAudioDevice(match);
      }
    }
  }

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    try {
      await _audioEngine.setEqualizer(equalizer);
    } catch (e) {
      debugPrint('[PlaybackController] setEqualizer error: $e');
    }
    notifyListeners();
  }

  Future<void> setReverb(Reverb reverb) async {
    try {
      await _audioEngine.setReverb(reverb);
    } catch (e) {
      debugPrint('[PlaybackController] setReverb error: $e');
    }
    notifyListeners();
  }

  Future<List<AudioDevice>> getAudioDevices() async {
    try {
      final devices = await _audioEngine.getAudioDevices();
      if (!_isDisposed && devices.isNotEmpty) {
        _audioDevices = devices;
        _applySavedDeviceIfAvailable(devices);
        notifyListeners();
      }
      return devices;
    } catch (e) {
      debugPrint('[PlaybackController] getAudioDevices error: $e');
      return const [];
    }
  }

  Future<bool> setAudioDevice(AudioDevice device) async {
    _currentDevice = device;
    try {
      final ok = await _audioEngine.setDevice(device);
      notifyListeners();
      return ok;
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
      _audioEngine.setInfiniteMix(enabled);
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
      await _audioEngine.play();
    } catch (e) {
      debugPrint('[PlaybackController] play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _audioEngine.pause();
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
      await _audioEngine.stop();
    } catch (e) {
      debugPrint('[PlaybackController] stop error: $e');
    }
  }

  Future<void> next() async {
    try {
      await _audioEngine.next();
    } catch (e) {
      debugPrint('[PlaybackController] next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await _audioEngine.previous();
    } catch (e) {
      debugPrint('[PlaybackController] previous error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await _audioEngine.seek(pos);
    } catch (e) {
      debugPrint('[PlaybackController] seek error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    try {
      await _audioEngine.setVolume(vol);
    } catch (e) {
      debugPrint('[PlaybackController] setVolume error: $e');
    }
  }

  Future<void> setRate(double rate) async {
    try {
      await _audioEngine.setRate(rate);
    } catch (e) {
      debugPrint('[PlaybackController] setRate error: $e');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _audioEngine.setPitch(pitch);
    } catch (e) {
      debugPrint('[PlaybackController] setPitch error: $e');
    }
  }

  Future<void> setShuffle(bool enabled) async {
    try {
      await _audioEngine.setShuffle(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setShuffle error: $e');
    }
  }

  Future<void> toggleShuffle() => setShuffle(!_state.shuffle);

  Future<void> setLoopMode(Loop loop) async {
    try {
      await _audioEngine.setLoopMode(loop);
    } catch (e) {
      debugPrint('[PlaybackController] setLoopMode error: $e');
    }
  }

  Future<void> toggleLoopMode() async {
    try {
      final nextMode = _state.loop.next();
      await _audioEngine.setLoopMode(nextMode);
    } catch (e) {
      debugPrint('[PlaybackController] toggleLoopMode error: $e');
    }
  }

  Future<void> cycleLoopMode() => toggleLoopMode();

  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    try {
      await _audioEngine.setCrossfadeConfig(config);
    } catch (e) {
      debugPrint('[PlaybackController] setCrossfadeConfig error: $e');
    }
  }

  Future<void> setSkipSilence(bool enabled) async {
    try {
      await _audioEngine.setSkipSilence(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setSkipSilence error: $e');
    }
  }

  Future<void> setVolumeNormalization(bool enabled) async {
    try {
      await _audioEngine.setVolumeNormalization(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setVolumeNormalization error: $e');
    }
  }

  Future<void> setPreamp(double preampDb) async {
    try {
      await _audioEngine.setPreamp(preampDb);
    } catch (e) {
      debugPrint('[PlaybackController] setPreamp error: $e');
    }
  }

  Future<void> setBalance(double balance) async {
    try {
      await _audioEngine.setBalance(balance);
    } catch (e) {
      debugPrint('[PlaybackController] setBalance error: $e');
    }
  }

  Future<void> setMono(bool enabled) async {
    try {
      await _audioEngine.setMono(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setMono error: $e');
    }
  }

  Future<void> setCrossfeed(CrossfeedMode mode) async {
    try {
      await _audioEngine.setCrossfeed(mode);
    } catch (e) {
      debugPrint('[PlaybackController] setCrossfeed error: $e');
    }
  }

  Future<void> setSpatializer(double width) async {
    try {
      await _audioEngine.setSpatializer(width);
    } catch (e) {
      debugPrint('[PlaybackController] setSpatializer error: $e');
    }
  }

  Future<void> setLimiter(bool enabled) async {
    try {
      await _audioEngine.setLimiter(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setLimiter error: $e');
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

    if (!_historyLoggedForCurrentTrack && newState.currentTrack != null) {
      final hasPlayedThreshold =
          newState.position.inSeconds > 15 ||
          (newState.duration.inMilliseconds > 0 && newState.progress >= 0.5);

      if (hasPlayedThreshold) {
        _historyLoggedForCurrentTrack = true;
        final trackId = newState.currentTrack!.id;
        if (trackId != null) {
          _store
              ?.addTracksToPlaylistInStore(AppDatabase.historyPlaylistId, [
                trackId,
              ])
              .catchError((e) {
                debugPrint(
                  '[PlaybackController] Failed to add track $trackId to history: $e',
                );
              });
        }
      }
    }
  }

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
        prev.hasPrevious != next.hasPrevious ||
        prev.hasNext != next.hasNext ||
        prev.isInfiniteMixEnabled != next.isInfiniteMixEnabled ||
        prev.currentTrack?.filePath != next.currentTrack?.filePath ||
        !listEquals(prev.playables, next.playables);
  }

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
    _visualizerSubscription?.cancel();
    _devicesSubscription?.cancel();
    if (_state.currentTrack != null) {
      _settingsRepository.setLastPlayed(
        filePath: _state.currentTrack!.filePath,
        positionMs: _positionNotifier.value.inMilliseconds,
      );
    }
    if (_ownsAudioEngine) {
      unawaited(_audioEngine.dispose());
    }
    _positionNotifier.dispose();
    super.dispose();
  }
}
