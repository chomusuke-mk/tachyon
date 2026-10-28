// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;

import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/database/app_database.dart' show AppDatabase;
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

export 'package:miniaudio_player/miniaudio_player.dart'
    show AudioDevice, CrossfeedMode, Equalizer, Reverb, EngineItem;
export 'package:tachyon/core/playback/domain/audio_playable.dart';
export 'package:tachyon/core/playback/domain/crossfade_config.dart';
export 'package:tachyon/core/playback/domain/loop_mode.dart';

class PlaybackController extends ChangeNotifier {
  final LibraryStore? _store;
  final SettingsRepository _settingsRepository;
  ma.MiniaudioEngine<AudioPlayable>? _engine;
  final bool _ownsEngine;

  final List<StreamSubscription<dynamic>> _engineSubscriptions = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<dynamic>? _visualizerSubscription;
  StreamSubscription<List<ma.AudioDevice>>? _devicesSubscription;
  PlaybackState _state = const PlaybackState.initial();

  ma.Equalizer _equalizer = ma.Equalizer.flat;
  ma.AudioDevice? _currentDevice;
  List<ma.AudioDevice> _audioDevices = const [];
  bool _isInfiniteMixEnabled = false;
  bool _isMinimized = false;
  bool _pauseOnDeviceChange = true;
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
    ma.MiniaudioEngine<AudioPlayable>? engine,
    Stream<List<ma.AudioDevice>>? devicesStream,
  }) : _store = store,
       _settingsRepository = settingsRepository,
       _ownsEngine = engine == null {
    _pauseOnDeviceChange = _settingsRepository.getPauseOnDeviceChange();

    if (engine != null) {
      _engine = engine;
      _bindEngine(engine);
      engine.action.setPauseOnDeviceChange(_pauseOnDeviceChange);
    }

    final devStream =
        devicesStream ??
        _safeGetAudioDevicesStream();

    _devicesSubscription = devStream?.listen((devices) {
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
      getAudioDevices();
    }
  }

  static Stream<List<ma.AudioDevice>>? _safeGetAudioDevicesStream() {
    try {
      return ma.MiniaudioPlayer.getAudioDevicesStream();
    } catch (_) {
      return null;
    }
  }

  ma.MiniaudioEngine<AudioPlayable> get engine {
    if (_engine == null) {
      final eng = ma.MiniaudioEngine<AudioPlayable>(
        pauseOnDeviceChange: _pauseOnDeviceChange,
        infiniteMixProvider: (count) async {
          final tracks = _store?.getRandomTracks(count) ?? const <Track>[];
          return [
            for (final t in tracks)
              t.toEngineItem(),
          ];
        },
      );
      _engine = eng;
      _bindEngine(eng);
    }
    return _engine!;
  }

  bool _syncScheduled = false;

  void _scheduleSyncState(ma.MiniaudioEngine<AudioPlayable> eng) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (!_isDisposed && _engine != null) {
        _syncStateFromEngine(eng);
      }
    });
  }

  void _bindEngine(ma.MiniaudioEngine<AudioPlayable> eng) {
    eng.action.setVisualizerEnabled(false);
    _syncStateFromEngine(eng);
    _isInfiniteMixEnabled = eng.state.infiniteMixEnabled;
    _positionNotifier.value = eng.state.position;

    _engineSubscriptions.add(
      eng.stream.playbackState.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.playing.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.buffering.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.completed.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.duration.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.queue.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.currentIndex.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.shuffle.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.loopMode.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.infiniteMixEnabled.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.volume.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.rate.listen((_) => _scheduleSyncState(eng)),
    );
    _engineSubscriptions.add(
      eng.stream.pitch.listen((_) => _scheduleSyncState(eng)),
    );

    _positionSubscription = eng.stream.position.listen((pos) {
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

    _visualizerSubscription = eng.stream.visualizer.listen((vis) {
      if (!_visualizerEnabled || _isMinimized) return;
      _visualizerNotifier.value = <double>[
        vis.rms,
        vis.peak,
        vis.left,
        vis.right,
        ...vis.bands,
      ];
    });
  }

  void _syncStateFromEngine(ma.MiniaudioEngine<AudioPlayable> eng) {
    final oldState = _state;
    final engState = eng.state;
    final queueItems = engState.queue;

    _state = PlaybackState(
      currentIndex: engState.currentIndex,
      queue: queueItems,
      isPlaying: engState.playing,
      isBuffering: engState.buffering,
      isCompleted: engState.completed,
      position: _positionNotifier.value,
      duration: engState.duration,
      rate: engState.rate,
      pitch: engState.pitch,
      volume: engState.volume,
      isShuffled: engState.shuffle,
      loopMode: engState.loopMode,
      crossfadeDuration: engState.crossfadeConfig.duration,
      skipSilence: engState.skipSilence,
      volumeNormalization: engState.volumeNormalization,
      isInfiniteMixEnabled: engState.infiniteMixEnabled,
      preampDb: engState.preamp,
      balance: engState.balance,
      mono: engState.mono,
      crossfeedMode: engState.crossfeed,
      spatializerWidth: engState.spatializerWidth,
      limiterEnabled: engState.limiterEnabled,
    );

    _isInfiniteMixEnabled = engState.infiniteMixEnabled;
    _checkHistoryLogging(_state);
    _checkStatePersistence(oldState, _state);

    if (_hasDiscreteStateChanged(oldState, _state)) {
      notifyListeners();
    }
  }

  AudioPlayable _canonicalPlayable(AudioPlayable playable) {
    if (playable is! Track) return playable;
    final store = _store;
    if (store == null) return playable;
    if (playable.id != null) {
      final existing = store.getTrackById(playable.id!);
      if (existing != null) return existing;
    }
    final existing = store.getTrackByPath(playable.filePath);
    return existing ?? playable;
  }

  // ---------------------------------------------------------------------------
  // Getters & Observables
  // ---------------------------------------------------------------------------
  PlaybackState get state => _state;
  ma.EngineItem<AudioPlayable>? get currentEntry =>
      _engine != null ? _engine!.state.currentItem : _state.currentEntry;
  AudioPlayable? get currentPlayable => currentEntry?.data;
  Track? get currentTrack {
    final p = currentPlayable;
    if (p is Track) return p;
    return _state.currentTrack;
  }

  bool isCurrentTrack(Track? track) {
    final cur = currentTrack;
    return track != null &&
        (cur == track ||
            (cur?.id != null && cur?.id == track.id) ||
            (cur?.filePath.isNotEmpty == true &&
                cur?.filePath == track.filePath));
  }

  bool get isPlaying => _engine?.state.playing ?? _state.isPlaying;
  bool get isBuffering => _engine?.state.buffering ?? _state.isBuffering;
  bool get isCompleted => _engine?.state.completed ?? _state.isCompleted;

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
    if (_engine != null) {
      _engine!.action.setVisualizerEnabled(enabled && !_isMinimized);
    }
  }

  void setMinimized(bool minimized) {
    if (_isMinimized == minimized) return;
    _isMinimized = minimized;
    if (_engine != null) {
      if (minimized) {
        _engine!.action.setVisualizerEnabled(false);
      } else {
        if (_visualizerEnabled) {
          _engine!.action.setVisualizerEnabled(true);
        }
        final livePos = _engine!.state.position;
        _lastPositionEmitTimestamp = DateTime.now().millisecondsSinceEpoch;
        _lastEmittedPositionMs = livePos.inMilliseconds;
        if (_positionNotifier.value != livePos) {
          _positionNotifier.value = livePos;
        }
      }
    }
  }

  Duration get duration => _engine?.state.duration ?? _state.duration;
  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;
  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  double get currentVisualAmplitude {
    if (!isPlaying) return 0.0;
    final track = currentTrack;
    return track?.getPointAtPosition(position, duration) ?? 0.0;
  }

  double get volume => _engine != null ? _engine!.state.volume : _state.volume;
  double get rate => _engine?.state.rate ?? _state.rate;
  double get pitch => _engine?.state.pitch ?? _state.pitch;

  LoopMode get loopMode => _engine?.state.loopMode ?? _state.loopMode;
  bool get isShuffled => _engine?.state.shuffle ?? _state.isShuffled;

  List<ma.EngineItem<AudioPlayable>> get queue =>
      _engine != null ? _engine!.state.queue : _state.queue;
  int get currentIndex => _engine?.state.currentIndex ?? _state.currentIndex;

  bool get hasNext => _engine?.state.hasNext ?? _state.hasNext;
  bool get hasPrevious => _engine?.state.hasPrevious ?? _state.hasPrevious;

  CrossfadeConfig get crossfadeConfig =>
      _engine != null
          ? CrossfadeConfig(
              duration: _engine!.state.crossfadeConfig.duration,
              manualDuration: _engine!.state.crossfadeConfig.manualDuration,
              curve: _engine!.state.crossfadeConfig.curve,
            )
          : _state.crossfadeConfig;

  bool get isCrossfading => _engine?.state.isCrossfading ?? false;
  double get crossfadeProgress => _engine?.state.crossfadeProgress ?? 0.0;

  bool get skipSilence => _engine?.state.skipSilence ?? _state.skipSilence;
  bool get volumeNormalization =>
      _engine?.state.volumeNormalization ?? _state.volumeNormalization;
  double get preampDb => _engine?.state.preamp ?? _state.preampDb;
  double get balance => _engine?.state.balance ?? _state.balance;
  double get spatializerWidth =>
      _engine?.state.spatializerWidth ?? _state.spatializerWidth;
  bool get mono => _engine?.state.mono ?? _state.mono;
  ma.CrossfeedMode get crossfeedMode =>
      _engine?.state.crossfeed ?? _state.crossfeedMode;
  bool get limiterEnabled =>
      _engine?.state.limiterEnabled ?? _state.limiterEnabled;
  ma.Reverb get reverb => _engine?.state.reverb ?? ma.Reverb.off;

  // ---------------------------------------------------------------------------
  // High-Level Track Selection & Queue Actions
  // ---------------------------------------------------------------------------
  Future<void> openTracks(
    List<AudioPlayable> tracks, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) return;
    final items = [
      for (int i = 0; i < tracks.length; i++)
        _canonicalPlayable(tracks[i]).toEngineItem(position: i),
    ];
    await engine.action.open(
      items,
      startIndex: startIndex,
      shuffle: shuffle,
    );
    if (play) {
      await engine.action.play();
    }
  }

  Future<void> playTrack(
    AudioPlayable track, {
    List<AudioPlayable>? contextTracks,
  }) async {
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
        shuffle: isShuffled,
      );
    } catch (e) {
      debugPrint('[PlaybackController] Error in playTrack: $e');
    }
  }

  Future<void> playAll(
    List<AudioPlayable> tracks, {
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

  Future<void> playNext(AudioPlayable track) async {
    try {
      final item = _canonicalPlayable(track).toEngineItem();
      await engine.action.insertNext(item);
    } catch (e) {
      debugPrint('[PlaybackController] Error in playNext: $e');
    }
  }

  Future<void> addToQueue(AudioPlayable track) async {
    await appendTracks([track]);
  }

  Future<void> appendTracks(List<AudioPlayable> tracks) async {
    if (tracks.isEmpty) return;
    try {
      final items = [
        for (final t in tracks)
          _canonicalPlayable(t).toEngineItem(),
      ];
      await engine.action.append(items);
    } catch (e) {
      debugPrint('[PlaybackController] Error in appendTracks: $e');
    }
  }

  Future<void> removeFromQueue(int index) async {
    try {
      await engine.action.removeAt(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in removeFromQueue: $e');
    }
  }

  Future<void> reorderQueue(int from, int to) async {
    try {
      await engine.action.reorder(from, to);
    } catch (e) {
      debugPrint('[PlaybackController] Error in reorderQueue: $e');
    }
  }

  Future<void> clearQueue() async {
    try {
      await engine.action.clearQueue();
    } catch (e) {
      debugPrint('[PlaybackController] Error in clearQueue: $e');
    }
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= queue.length) return;
    try {
      await engine.action.skipToIndex(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in skipToQueueIndex: $e');
    }
  }

  ma.Equalizer get equalizer => _equalizer;
  ma.AudioDevice? get currentDevice => _currentDevice;
  List<ma.AudioDevice> get audioDevices => _audioDevices;
  Stream<List<ma.AudioDevice>> get devicesStream =>
      _safeGetAudioDevicesStream() ?? const Stream.empty();

  void _applySavedDeviceIfAvailable(List<ma.AudioDevice> devices) {
    final savedId = _settingsRepository.getSettings().audioOutputDeviceId;
    if (savedId != null && savedId.isNotEmpty && _currentDevice == null) {
      final match = devices.where((d) => d.id == savedId).firstOrNull;
      if (match != null) {
        setAudioDevice(match);
      }
    }
  }

  Future<void> setEqualizer(ma.Equalizer equalizer) async {
    _equalizer = equalizer;
    try {
      await engine.action.setEqualizer(equalizer);
    } catch (e) {
      debugPrint('[PlaybackController] setEqualizer error: $e');
    }
  }

  Future<void> setReverb(ma.Reverb reverb) async {
    try {
      await engine.action.setReverb(reverb);
    } catch (e) {
      debugPrint('[PlaybackController] setReverb error: $e');
    }
  }

  Future<List<ma.AudioDevice>> getAudioDevices() async {
    try {
      final devices = await ma.MiniaudioPlayer.getAudioDevices();
      if (!_isDisposed && devices.isNotEmpty) {
        _audioDevices = devices;
        _applySavedDeviceIfAvailable(devices);
      }
      return devices;
    } catch (e) {
      debugPrint('[PlaybackController] getAudioDevices error: $e');
      return const [];
    }
  }

  Future<bool> setAudioDevice(ma.AudioDevice device) async {
    _currentDevice = device;
    try {
      await engine.action.setDevice(device);
      return true;
    } catch (e) {
      debugPrint('[PlaybackController] setAudioDevice error: $e');
      return false;
    }
  }

  bool get pauseOnDeviceChange => _pauseOnDeviceChange;

  Future<void> setPauseOnDeviceChange(bool pause) async {
    _pauseOnDeviceChange = pause;
    if (_engine != null) {
      _engine!.action.setPauseOnDeviceChange(pause);
    }
  }

  bool get isInfiniteMixEnabled => _isInfiniteMixEnabled;

  void setInfiniteMix(bool enabled) {
    _isInfiniteMixEnabled = enabled;
    try {
      engine.action.setInfiniteMix(enabled);
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
      await engine.action.play();
    } catch (e) {
      debugPrint('[PlaybackController] play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await engine.action.pause();
    } catch (e) {
      debugPrint('[PlaybackController] pause error: $e');
    }
  }

  Future<void> playOrPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> stop() async {
    try {
      await engine.action.stop();
    } catch (e) {
      debugPrint('[PlaybackController] stop error: $e');
    }
  }

  Future<void> next() async {
    try {
      await engine.action.next();
    } catch (e) {
      debugPrint('[PlaybackController] next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await engine.action.previous();
    } catch (e) {
      debugPrint('[PlaybackController] previous error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      await engine.action.seek(pos);
    } catch (e) {
      debugPrint('[PlaybackController] seek error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    try {
      final clamped = vol.clamp(0.0, 2.0);
      _state = _state.copyWith(volume: clamped);
      notifyListeners();
      await engine.action.setVolume(clamped);
    } catch (e) {
      debugPrint('[PlaybackController] setVolume error: $e');
    }
  }

  Future<void> setRate(double rate) async {
    try {
      final clamped = rate.clamp(
        AppDefaults.playbackRateMin,
        AppDefaults.playbackRateMax,
      );
      _state = _state.copyWith(rate: clamped);
      notifyListeners();
      await engine.action.setRate(clamped);
    } catch (e) {
      debugPrint('[PlaybackController] setRate error: $e');
    }
  }

  Future<void> setPitch(double pitch) async {
    try {
      final clamped = pitch.clamp(
        AppDefaults.playbackPitchMin,
        AppDefaults.playbackPitchMax,
      );
      _state = _state.copyWith(pitch: clamped);
      notifyListeners();
      await engine.action.setPitch(clamped);
    } catch (e) {
      debugPrint('[PlaybackController] setPitch error: $e');
    }
  }

  Future<void> setShuffle(bool enabled) async {
    try {
      await engine.action.setShuffle(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setShuffle error: $e');
    }
  }

  Future<void> toggleShuffle() => setShuffle(!isShuffled);

  Future<void> setLoopMode(LoopMode loop) async {
    try {
      await engine.action.setLoopMode(loop);
    } catch (e) {
      debugPrint('[PlaybackController] setLoopMode error: $e');
    }
  }

  Future<void> toggleLoopMode() async {
    try {
      final nextMode = loopMode.next();
      await setLoopMode(nextMode);
    } catch (e) {
      debugPrint('[PlaybackController] toggleLoopMode error: $e');
    }
  }

  Future<void> setCrossfadeConfig(CrossfadeConfig config) async {
    try {
      await engine.action.setCrossfadeConfig(
        ma.CrossfadeConfig(
          duration: config.duration,
          manualDuration: config.manualDuration,
          curve: config.curve,
        ),
      );
    } catch (e) {
      debugPrint('[PlaybackController] setCrossfadeConfig error: $e');
    }
  }

  Future<void> setSkipSilence(bool enabled) async {
    try {
      await engine.action.setSkipSilence(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setSkipSilence error: $e');
    }
  }

  Future<void> setVolumeNormalization(bool enabled) async {
    try {
      await engine.action.setVolumeNormalization(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setVolumeNormalization error: $e');
    }
  }

  Future<void> setPreamp(double preampDb) async {
    try {
      await engine.action.setPreamp(preampDb);
    } catch (e) {
      debugPrint('[PlaybackController] setPreamp error: $e');
    }
  }

  Future<void> setBalance(double balance) async {
    try {
      await engine.action.setBalance(balance);
    } catch (e) {
      debugPrint('[PlaybackController] setBalance error: $e');
    }
  }

  Future<void> setMono(bool enabled) async {
    try {
      await engine.action.setMono(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setMono error: $e');
    }
  }

  Future<void> setCrossfeed(ma.CrossfeedMode mode) async {
    try {
      await engine.action.setCrossfeed(mode);
    } catch (e) {
      debugPrint('[PlaybackController] setCrossfeed error: $e');
    }
  }

  Future<void> setSpatializer(double width) async {
    try {
      await engine.action.setSpatializer(enabled: width > 0, width: width);
    } catch (e) {
      debugPrint('[PlaybackController] setSpatializer error: $e');
    }
  }

  Future<void> setLimiter(bool enabled) async {
    try {
      await engine.action.setLimiter(enabled);
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
    return prev.currentIndex != next.currentIndex ||
        prev.isPlaying != next.isPlaying ||
        prev.isBuffering != next.isBuffering ||
        prev.isCompleted != next.isCompleted ||
        prev.duration != next.duration ||
        prev.rate != next.rate ||
        prev.pitch != next.pitch ||
        prev.volume != next.volume ||
        prev.isShuffled != next.isShuffled ||
        prev.loopMode != next.loopMode ||
        prev.hasPrevious != next.hasPrevious ||
        prev.hasNext != next.hasNext ||
        prev.isInfiniteMixEnabled != next.isInfiniteMixEnabled ||
        prev.currentTrack?.filePath != next.currentTrack?.filePath ||
        !listEquals(prev.queue, next.queue);
  }

  void _checkStatePersistence(PlaybackState oldState, PlaybackState newState) {
    final current = newState.currentTrack;
    if (current == null) return;

    final isTrackTransition =
        oldState.currentTrack?.filePath != current.filePath;
    final isPauseTransition = oldState.isPlaying && !newState.isPlaying;
    final isSeekTransition =
        (newState.position - oldState.position).abs() >
        const Duration(seconds: 2);
    final isStopOrCompleted = oldState.isPlaying && newState.isCompleted;

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

    if (newState.isPlaying) {
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
    final current = currentTrack;
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
    for (final sub in _engineSubscriptions) {
      sub.cancel();
    }
    _engineSubscriptions.clear();
    _positionSubscription?.cancel();
    _visualizerSubscription?.cancel();
    _devicesSubscription?.cancel();
    final current = currentTrack;
    if (current != null) {
      _settingsRepository.setLastPlayed(
        filePath: current.filePath,
        positionMs: _positionNotifier.value.inMilliseconds,
      );
    }
    if (_ownsEngine && _engine != null) {
      unawaited(_engine!.dispose());
    }
    _positionNotifier.dispose();
    super.dispose();
  }
}
