// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;

import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/metadata/domain/scan_progress.dart';
import 'package:tachyon/core/metadata/metadata_service.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/playback_state.dart';
import 'package:tachyon/core/playback/domain/resolved_playback_metadata.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';

export 'package:miniaudio_player/miniaudio_player.dart'
    show
        AudioDevice,
        AudioInfo,
        AudioMetadata,
        AudioSource,
        Buffer,
        Crossfeed,
        Equalizer,
        MiniaudioPlayerException,
        ReplayGainMode,
        Reverb,
        SilenceSkipConfig,
        SilenceSkipMode,
        VisualizerData;
export 'package:tachyon/core/playback/domain/audio_playable.dart';
export 'package:tachyon/core/playback/domain/crossfade_config.dart';
export 'package:tachyon/core/playback/domain/loop_mode.dart';
export 'package:tachyon/core/playback/domain/resolved_playback_metadata.dart';

class _DomainNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class PlaybackController extends ChangeNotifier {
  final LibraryStore? _store;
  final SettingsRepository _settingsRepository;
  final Stream<List<ma.AudioDevice>>? _injectedDevicesStream;
  ma.MiniaudioPlayer<AudioPlayable>? _player;
  final bool _ownsEngine;

  final List<StreamSubscription<dynamic>> _engineSubscriptions = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<ma.VisualizerData>? _visualizerSubscription;
  StreamSubscription<List<ma.AudioDevice>>? _devicesSubscription;
  StreamSubscription<ScanProgress>? _scanProgressSubscription;
  PlaybackState _state = const PlaybackState.initial();

  ma.Equalizer _equalizer = ma.Equalizer.flat;
  ma.AudioDevice? _currentDevice;
  List<ma.AudioDevice> _audioDevices = const [];
  bool _isInfiniteMixEnabled = false;
  bool _isMinimized = false;
  bool _pauseOnDeviceChange = true;
  bool _wasPlayingBeforeStop = false;
  bool _isLibraryScanActive = false;
  Track? _lastCanonicalCurrentTrack;
  int _lastPositionEmitTimestamp = 0;
  int _lastEmittedPositionMs = -1;

  // Scoped domain listenables (fine-grained UI rebuilds)
  final _DomainNotifier _trackNotifier = _DomainNotifier();
  final _DomainNotifier _transportNotifier = _DomainNotifier();
  final _DomainNotifier _controlsNotifier = _DomainNotifier();
  final _DomainNotifier _tuningNotifier = _DomainNotifier();
  final _DomainNotifier _queueNotifier = _DomainNotifier();
  final _DomainNotifier _devicesNotifier = _DomainNotifier();

  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<int> _positionSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<ma.Buffer> _bufferNotifier = ValueNotifier<ma.Buffer>(
    const ma.Buffer(),
  );
  final ValueNotifier<ma.VisualizerData> _visualizerDataNotifier =
      ValueNotifier<ma.VisualizerData>(ma.VisualizerData.empty());
  final ValueNotifier<ma.AudioMetadata?> _liveMetadataNotifier =
      ValueNotifier<ma.AudioMetadata?>(null);
  final ValueNotifier<ma.AudioInfo?> _audioInfoNotifier =
      ValueNotifier<ma.AudioInfo?>(null);
  final ValueNotifier<Duration> _silenceSavedDurationNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final StreamController<ma.MiniaudioPlayerException> _errorsController =
      StreamController<ma.MiniaudioPlayerException>.broadcast();

  // Coalesced latest-wins RPC lanes (no timers)
  final Map<String, Future<void>> _rpcInFlight = {};
  final Map<String, Future<void> Function()> _rpcPending = {};

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
  bool _inScopedNotify = false;
  String? _currentlyLoggedHistoryFilePath;
  bool _historyLoggedForCurrentTrack = false;
  String? _lastActivePlayableKey;

  PlaybackController({
    LibraryStore? store,
    required SettingsRepository settingsRepository,
    MetadataService? metadataService,
    ma.MiniaudioPlayer<AudioPlayable>? engine,
    Stream<List<ma.AudioDevice>>? devicesStream,
  }) : _store = store,
       _settingsRepository = settingsRepository,
       _injectedDevicesStream = devicesStream,
       _ownsEngine = engine == null {
    _pauseOnDeviceChange = _settingsRepository.getPauseOnDeviceChange();

    if (store != null) {
      store.addListener(_onLibraryStoreUpdated);
    }

    if (metadataService != null) {
      _isLibraryScanActive = metadataService.isScanning;
      _scanProgressSubscription = metadataService.progressStream.listen((
        progress,
      ) {
        setLibraryAnalysisActive(progress.isRunning);
      });
    }

    if (engine != null) {
      _player = engine;
      _bindEngine(engine);
      unawaited(engine.action.setPauseOnDeviceChange(_pauseOnDeviceChange));
    }

    if (devicesStream != null) {
      _devicesSubscription = devicesStream.listen((devices) {
        if (!_isDisposed) {
          _audioDevices = devices;
          _applySavedDeviceIfAvailable(devices);
          _emitScoped([_devicesNotifier]);
        }
      });
    }
  }

  ma.MiniaudioPlayer<AudioPlayable> get player {
    if (_player == null) {
      final eng = ma.MiniaudioPlayer<AudioPlayable>(
        config: ma.PlayerConfig(
          pauseOnDeviceChange: _pauseOnDeviceChange,
          visualizerSource: ma.AudioOutputSource.musicMix,
        ),
      );
      eng.action.setInfiniteMixProvider((count) async {
        final tracks = _store?.getRandomTracks(count) ?? const <Track>[];
        return [for (final t in tracks) t.toAudioSource()];
      });
      _player = eng;
      _bindEngine(eng);
    }
    return _player!;
  }

  void _emitScoped(List<_DomainNotifier> domains) {
    if (_isDisposed) return;
    for (final d in domains) {
      d.notify();
    }
    _inScopedNotify = true;
    try {
      super.notifyListeners();
    } finally {
      _inScopedNotify = false;
    }
  }

  Future<void> _coalesceRpc(String key, Future<void> Function() task) {
    final existing = _rpcInFlight[key];
    if (existing != null) {
      _rpcPending[key] = task;
      return existing;
    }
    Future<void> drain() async {
      var current = task;
      while (true) {
        try {
          await current();
        } catch (e) {
          debugPrint('[PlaybackController] RPC ($key) error: $e');
        }
        final next = _rpcPending.remove(key);
        if (next == null || _isDisposed) break;
        current = next;
      }
    }

    late final Future<void> tracked;
    var syncCompleted = false;
    tracked = drain().whenComplete(() {
      syncCompleted = true;
      if (identical(_rpcInFlight[key], tracked)) {
        _rpcInFlight.remove(key);
      }
    });
    if (!syncCompleted) {
      _rpcInFlight[key] = tracked;
    }
    return tracked;
  }

  void _bindEngine(ma.MiniaudioPlayer<AudioPlayable> player) {
    unawaited(
      player.action.setVisualizerEnabled(_visualizerEnabled && !_isMinimized),
    );
    _syncSnapshotFromEngine(player, notifyAll: true);
    _isInfiniteMixEnabled = player.state.infiniteMixEnabled;
    _setPosition(player.state.position);
    _volumeNotifier.value = player.state.volume;
    _bufferNotifier.value = player.state.buffer;
    _audioInfoNotifier.value = player.state.audioInfo;
    _silenceSavedDurationNotifier.value = player.state.silenceSavedDuration;
    _syncMetadataEnabled();

    _engineSubscriptions.addAll([
      player.stream.playbackState.listen((pbState) {
        if (_isDisposed) return;
        final engState = player.state;
        final isCompleted =
            pbState.isStopped &&
            engState.queue.isNotEmpty &&
            _wasPlayingBeforeStop;
        if (pbState.isPlaying) {
          _wasPlayingBeforeStop = true;
        } else if (engState.queue.isEmpty) {
          _wasPlayingBeforeStop = false;
        }
        final oldState = _state;
        if (oldState.isPlaying == engState.isPlaying &&
            oldState.isBuffering == engState.isBuffering &&
            oldState.isCompleted == isCompleted) {
          return;
        }
        _state = _state.copyWith(
          isPlaying: engState.isPlaying,
          isBuffering: engState.isBuffering,
          isCompleted: isCompleted,
        );
        _checkStatePersistence(oldState, _state);
        _emitScoped([_transportNotifier]);
      }),
      player.stream.isPlaying.listen((playing) {
        if (_isDisposed) return;
        if (playing) {
          _wasPlayingBeforeStop = true;
        }
        final nextCompleted =
            !playing &&
            player.state.playbackState.isStopped &&
            player.state.queue.isNotEmpty &&
            _wasPlayingBeforeStop;
        final oldState = _state;
        if (oldState.isPlaying == playing &&
            oldState.isCompleted == nextCompleted) {
          return;
        }
        _state = _state.copyWith(
          isPlaying: playing,
          isCompleted: nextCompleted,
        );
        _checkStatePersistence(oldState, _state);
        _emitScoped([_transportNotifier]);
      }),
      player.stream.isBuffering.listen((buffering) {
        if (_isDisposed || _state.isBuffering == buffering) return;
        _state = _state.copyWith(isBuffering: buffering);
        _emitScoped([_transportNotifier]);
      }),
      player.stream.currentItem.listen((item) {
        if (_isDisposed) return;
        _onTrackContextUpdated(player, item?.data);
      }),
      player.stream.currentIndex.listen((idx) {
        if (_isDisposed) return;
        final nextIdx = idx ?? 0;
        if (_state.currentIndex == nextIdx &&
            player.state.currentItem?.data?.filePath ==
                _lastActivePlayableKey) {
          return;
        }
        _state = _state.copyWith(currentIndex: nextIdx);
        _onTrackContextUpdated(player, player.state.currentItem?.data);
      }),
      player.stream.duration.listen((dur) {
        if (_isDisposed) return;
        final nextDur = dur ?? Duration.zero;
        final durChanged = _state.duration != nextDur;
        _state = _state.copyWith(duration: nextDur);
        final cur = currentPlayable;
        if (_isLibraryScanActive &&
            dur != null &&
            dur > Duration.zero &&
            cur is Track &&
            (cur.isMetadataPending || cur.id == null) &&
            cur.durationMs <= 0) {
          _store?.updatePendingTrackFromLivePlayback(
            filePath: cur.filePath,
            duration: dur,
          );
        }
        if (durChanged) {
          _emitScoped([_trackNotifier]);
        }
      }),
      player.stream.queue.listen((q) {
        if (_isDisposed) return;
        _state = _state.copyWith(
          queue: q,
          currentIndex: player.state.currentIndex ?? 0,
        );
        _emitScoped([_queueNotifier, _transportNotifier]);
      }),
      player.stream.isShuffled.listen((shuffled) {
        if (_isDisposed || _state.isShuffled == shuffled) return;
        _state = _state.copyWith(isShuffled: shuffled);
        _emitScoped([_controlsNotifier]);
      }),
      player.stream.loopMode.listen((loop) {
        if (_isDisposed || _state.loopMode == loop) return;
        _state = _state.copyWith(loopMode: loop);
        _emitScoped([_controlsNotifier, _transportNotifier]);
      }),
      player.stream.infiniteMixEnabled.listen((enabled) {
        if (_isDisposed || _isInfiniteMixEnabled == enabled) return;
        _isInfiniteMixEnabled = enabled;
        _state = _state.copyWith(isInfiniteMixEnabled: enabled);
        _emitScoped([_controlsNotifier, _queueNotifier]);
      }),
      player.stream.isCrossfading.listen((_) {
        if (_isDisposed) return;
        _emitScoped([_controlsNotifier]);
      }),
      player.stream.volume.listen((vol) {
        if (_isDisposed || _rpcInFlight.containsKey('volume')) return;
        _state = _state.copyWith(volume: vol);
        _volumeNotifier.value = vol;
        _emitScoped([_tuningNotifier]);
      }),
      player.stream.rate.listen((r) {
        if (_isDisposed || _rpcInFlight.containsKey('rate')) return;
        _state = _state.copyWith(rate: r);
        _emitScoped([_tuningNotifier]);
      }),
      player.stream.pitch.listen((pVal) {
        if (_isDisposed || _rpcInFlight.containsKey('pitch')) return;
        _state = _state.copyWith(pitch: pVal);
        _emitScoped([_tuningNotifier]);
      }),
      player.stream.buffer.listen((buf) {
        if (_isDisposed) return;
        _bufferNotifier.value = buf;
        if (_state.isBuffering != buf.isBuffering) {
          _state = _state.copyWith(isBuffering: buf.isBuffering);
          _emitScoped([_transportNotifier]);
        }
      }),
      player.stream.metadata.listen((meta) {
        if (_isDisposed) return;
        final playable = currentPlayable;
        if (playable == null) return;
        if (playable.isStream) {
          _liveMetadataNotifier.value = meta;
          _emitScoped([_trackNotifier]);
        } else if (_isLibraryScanActive &&
            playable is Track &&
            (playable.isMetadataPending || playable.id == null)) {
          _liveMetadataNotifier.value = meta;
          _emitScoped([_trackNotifier]);
          if (meta != null) {
            _enrichPendingTrackFromLivePlayback(
              playable.filePath,
              metadata: meta,
              audioInfo: _audioInfoNotifier.value,
            );
          }
        }
      }),
      player.stream.audioInfo.listen((info) {
        if (_isDisposed) return;
        _audioInfoNotifier.value = info;
        _state = _state.copyWith(
          audioBitrate: info?.bitrate.toDouble(),
          audioSampleRate: info?.sampleRate,
          audioChannels: info?.channels,
        );
        final playable = currentPlayable;
        if (playable?.isStream == true) {
          _emitScoped([_trackNotifier]);
        } else if (_isLibraryScanActive &&
            info != null &&
            playable is Track &&
            (playable.isMetadataPending || playable.id == null)) {
          _enrichPendingTrackFromLivePlayback(
            playable.filePath,
            audioInfo: info,
          );
        }
      }),
      player.stream.silenceSavedDuration.listen((saved) {
        if (_isDisposed) return;
        _silenceSavedDurationNotifier.value = saved;
      }),
      player.stream.errors.listen((err) {
        if (!_isDisposed && !_errorsController.isClosed) {
          debugPrint('[PlaybackController] Native player error: $err');
          _errorsController.add(err);
        }
      }),
      player.stream.outputs.listen((outputs) {
        if (_isDisposed) return;
        final activeId = outputs.firstOrNull?.deviceId;
        if (activeId != null && _audioDevices.isNotEmpty) {
          final match = _audioDevices
              .where(
                (d) =>
                    (activeId == 'AUTO' && d.isAuto) || d.id == activeId,
              )
              .firstOrNull;
          if (match != null && match != _currentDevice) {
            _currentDevice = match;
            _emitScoped([_devicesNotifier]);
          }
        }
      }),
    ]);

    if (_injectedDevicesStream == null) {
      _devicesSubscription = player.stream.globalOutputDevices.listen((
        devices,
      ) {
        if (_isDisposed) return;
        _audioDevices = devices;
        _applySavedDeviceIfAvailable(devices);
        _emitScoped([_devicesNotifier]);
      });
    }

    _positionSubscription = player.stream.position.listen((pos) {
      if (_isDisposed) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final deltaMs = now - _lastPositionEmitTimestamp;
      final minIntervalMs = _isMinimized ? 5000 : 33;
      final jumpThresholdMs = _isMinimized ? 2000 : 1000;
      if (deltaMs < minIntervalMs &&
          (pos.inMilliseconds - _lastEmittedPositionMs).abs() <=
              jumpThresholdMs) {
        return;
      }
      _lastPositionEmitTimestamp = now;
      _lastEmittedPositionMs = pos.inMilliseconds;

      _setPosition(pos);
      if ((pos.inMilliseconds - _state.position.inMilliseconds).abs() >= 1000) {
        final oldState = _state;
        _state = _state.copyWith(position: pos);
        _checkHistoryLogging(_state);
        _checkStatePersistence(oldState, _state);
      }
    });

    _visualizerSubscription = player.stream.visualizer.listen((vis) {
      if (!_visualizerEnabled || _isMinimized || _isDisposed) return;
      _visualizerDataNotifier.value = vis;
    });
  }

  void _setPosition(Duration pos) {
    if (_positionNotifier.value != pos) {
      _positionNotifier.value = pos;
    }
    final sec = pos.inSeconds;
    if (_positionSecondsNotifier.value != sec) {
      _positionSecondsNotifier.value = sec;
    }
  }

  bool get isLibraryAnalysisActive => _isLibraryScanActive;

  void setLibraryAnalysisActive(bool active) {
    if (_isLibraryScanActive == active) return;
    _isLibraryScanActive = active;
    _syncMetadataEnabled();
    if (!active &&
        currentPlayable?.isStream != true &&
        _liveMetadataNotifier.value != null) {
      _liveMetadataNotifier.value = null;
      _emitScoped([_trackNotifier]);
    }
  }

  bool _shouldEnableMetadataFor(AudioPlayable? playable) {
    if (playable?.isStream == true) return true;
    return _isLibraryScanActive;
  }

  void _syncMetadataEnabled() {
    final p = _player;
    if (p == null || _isDisposed) return;
    final wantMetadata = _shouldEnableMetadataFor(currentPlayable);
    if (p.state.metadataEnabled != wantMetadata) {
      unawaited(p.action.setMetadataEnabled(wantMetadata).catchError((_) {}));
    }
  }

  Future<void> _ensureMetadataEnabledFor(AudioPlayable? playable) async {
    final p = player;
    if (_isDisposed) return;
    final wantMetadata = _shouldEnableMetadataFor(playable);
    if (p.state.metadataEnabled != wantMetadata) {
      try {
        await p.action.setMetadataEnabled(wantMetadata);
      } catch (_) {}
    }
  }

  void _enrichPendingTrackFromLivePlayback(
    String filePath, {
    ma.AudioMetadata? metadata,
    ma.AudioInfo? audioInfo,
  }) {
    final store = _store;
    if (store == null || _isDisposed) return;
    store.updatePendingTrackFromLivePlayback(
      filePath: filePath,
      metadata: metadata,
      audioInfo: audioInfo,
    );

    if (metadata != null &&
        metadata.pictures.isNotEmpty &&
        MetadataUtils.thumbnailsDirectory != null &&
        MetadataUtils.tempDirectory != null) {
      final pic = MetadataUtils.pickBestCoverPicture(metadata.pictures);
      if (pic != null && pic.bytes.isNotEmpty) {
        unawaited(
          MetadataUtils.saveCoverBytes(pic.bytes)
              .then((hash) {
                if (!_isDisposed && hash != null) {
                  _store?.updatePendingTrackFromLivePlayback(
                    filePath: filePath,
                    artworkUri: hash,
                  );
                }
              })
              .catchError((Object _) {}),
        );
      }
    }
  }

  void _onLibraryStoreUpdated() {
    if (_isDisposed) return;
    final store = _store;
    if (store == null) return;

    final cur = currentTrack;
    final currentChanged = !identical(cur, _lastCanonicalCurrentTrack);
    if (currentChanged) {
      _lastCanonicalCurrentTrack = cur;
      if (cur != null &&
          !cur.isMetadataPending &&
          cur.id != null &&
          _liveMetadataNotifier.value != null) {
        _liveMetadataNotifier.value = null;
      }
      _checkHistoryLogging(_state);
      _syncMetadataEnabled();
      _emitScoped([_trackNotifier, _queueNotifier]);
      return;
    }

    if (queue.isNotEmpty) {
      var queueUpgraded = false;
      for (final item in queue) {
        final raw = item.data;
        if (raw is Track && !identical(_canonicalPlayable(raw), raw)) {
          queueUpgraded = true;
          break;
        }
      }
      if (queueUpgraded) {
        _emitScoped([_queueNotifier]);
      }
    }
  }

  void _onTrackContextUpdated(
    ma.MiniaudioPlayer<AudioPlayable> player,
    AudioPlayable? playable,
  ) {
    final oldState = _state;
    final engState = player.state;
    final resolved = playable != null ? _canonicalPlayable(playable) : null;
    if (resolved is Track) {
      _lastCanonicalCurrentTrack = resolved;
    } else {
      _lastCanonicalCurrentTrack = null;
    }
    final playableKey = resolved?.filePath;
    if (playableKey != _lastActivePlayableKey) {
      _lastActivePlayableKey = playableKey;
      _wasPlayingBeforeStop = engState.isPlaying;
      _liveMetadataNotifier.value = null;
      _audioInfoNotifier.value = null;
      _syncMetadataEnabled();
    }

    _state = _state.copyWith(
      currentIndex: engState.currentIndex ?? 0,
      queue: engState.queue,
      duration: engState.duration ?? Duration.zero,
      isCompleted:
          engState.playbackState.isStopped &&
          engState.queue.isNotEmpty &&
          _wasPlayingBeforeStop,
    );
    _checkHistoryLogging(_state);
    _checkStatePersistence(oldState, _state);
    _emitScoped([_trackNotifier, _queueNotifier, _transportNotifier]);
  }

  void _syncSnapshotFromEngine(
    ma.MiniaudioPlayer<AudioPlayable> eng, {
    bool notifyAll = false,
  }) {
    final engState = eng.state;
    _state = PlaybackState(
      currentIndex: engState.currentIndex ?? 0,
      queue: engState.queue,
      isPlaying: engState.isPlaying,
      isBuffering: engState.isBuffering,
      isCompleted:
          engState.playbackState.isStopped &&
          engState.queue.isNotEmpty &&
          _wasPlayingBeforeStop,
      position: _positionNotifier.value,
      duration: engState.duration ?? Duration.zero,
      rate: engState.rate,
      pitch: engState.pitch,
      volume: engState.volume,
      isShuffled: engState.isShuffled,
      loopMode: engState.loopMode,
      crossfadeDuration: engState.crossfadeConfig.autoDuration,
      skipSilence: engState.skipSilence,
      silenceSkipMode: engState.silenceSkipMode,
      volumeNormalization: engState.volumeNormalization,
      replayGainMode: engState.replayGainMode,
      isInfiniteMixEnabled: engState.infiniteMixEnabled,
      preampDb: engState.preamp,
      balance: engState.balance,
      mono: engState.mono,
      crossfeed: engState.crossfeed,
      spatializerWidth: engState.spatializerWidth,
      limiterEnabled: engState.limiterEnabled,
    );
    if (notifyAll) {
      _emitScoped([
        _trackNotifier,
        _transportNotifier,
        _controlsNotifier,
        _tuningNotifier,
        _queueNotifier,
        _devicesNotifier,
      ]);
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
  // Scoped Listenables & Observables
  // ---------------------------------------------------------------------------
  Listenable get trackListenable => _trackNotifier;
  Listenable get transportListenable => _transportNotifier;
  Listenable get controlsListenable => _controlsNotifier;
  ValueListenable<double> get volumeListenable => _volumeNotifier;
  Listenable get tuningListenable => _tuningNotifier;
  Listenable get queueListenable => _queueNotifier;
  Listenable get devicesListenable => _devicesNotifier;

  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueListenable<Duration> get positionListenable => _positionNotifier;
  ValueListenable<int> get positionSecondsListenable =>
      _positionSecondsNotifier;
  ValueListenable<ma.Buffer> get bufferListenable => _bufferNotifier;
  ValueListenable<ma.VisualizerData> get visualizerDataListenable =>
      _visualizerDataNotifier;
  ValueListenable<ma.AudioMetadata?> get liveMetadataListenable =>
      _liveMetadataNotifier;
  ValueListenable<ma.AudioInfo?> get audioInfoListenable => _audioInfoNotifier;
  ValueListenable<Duration> get silenceSavedDurationListenable =>
      _silenceSavedDurationNotifier;
  Stream<ma.MiniaudioPlayerException> get errorsStream =>
      _errorsController.stream;

  AudioPlayable resolvePlayable(AudioPlayable playable) =>
      _canonicalPlayable(playable);

  ResolvedPlaybackMetadata? get currentDisplayMetadata {
    final playable = currentPlayable;
    if (playable == null) return null;
    return ResolvedPlaybackMetadata.resolve(
      playable: playable,
      liveMetadata: _liveMetadataNotifier.value,
      liveAudioInfo: _audioInfoNotifier.value,
    );
  }

  PlaybackState get state => _state;
  ma.AudioSource<AudioPlayable>? get currentEntry =>
      _player != null ? _player!.state.currentItem : _state.currentEntry;
  AudioPlayable? get currentPlayable {
    final raw = currentEntry?.data ?? _state.currentPlayable ?? currentTrack;
    if (raw == null) return null;
    return _canonicalPlayable(raw);
  }

  Track? get currentTrack {
    final raw =
        currentEntry?.data ?? _state.currentPlayable ?? _state.currentTrack;
    if (raw is Track) {
      final canonical = _canonicalPlayable(raw);
      return canonical is Track ? canonical : raw;
    }
    return null;
  }

  bool isCurrentTrack(Track? track) {
    final cur = currentTrack;
    return track != null &&
        (cur == track ||
            (cur?.id != null && cur?.id == track.id) ||
            (cur?.filePath.isNotEmpty == true &&
                cur?.filePath == track.filePath));
  }

  bool get isPlaying => _player?.state.isPlaying ?? _state.isPlaying;
  bool get isBuffering => _player?.state.isBuffering ?? _state.isBuffering;
  bool get isCompleted => _state.isCompleted;
  bool get isLiveStream =>
      currentPlayable?.isStream ??
      (_player != null &&
          _player!.state.currentItem != null &&
          _player!.state.duration == null) ||
      _state.isLiveStream;

  Duration get position => _positionNotifier.value;
  ma.Buffer get buffer => _bufferNotifier.value;
  ma.AudioMetadata? get liveMetadata => _liveMetadataNotifier.value;
  ma.AudioInfo? get liveAudioInfo => _audioInfoNotifier.value;
  Duration get silenceSavedDuration => _silenceSavedDurationNotifier.value;

  bool _visualizerEnabled = false;

  void setVisualizerEnabled(bool enabled) {
    _visualizerEnabled = enabled;
    if (!enabled) {
      scheduleMicrotask(() {
        if (!_visualizerEnabled && !_isDisposed) {
          _visualizerDataNotifier.value = ma.VisualizerData.empty();
        }
      });
    }
    if (_player != null) {
      unawaited(
        _player!.action
            .setVisualizerEnabled(enabled && !_isMinimized)
            .catchError((_) {}),
      );
    }
  }

  void setMinimized(bool minimized) {
    if (_isMinimized == minimized) return;
    _isMinimized = minimized;
    if (_player != null) {
      if (minimized) {
        unawaited(_player!.action.setVisualizerEnabled(false).catchError((_) {}));
      } else {
        if (_visualizerEnabled) {
          unawaited(
            _player!.action.setVisualizerEnabled(true).catchError((_) {}),
          );
        }
        final livePos = _player!.state.position;
        _lastPositionEmitTimestamp = DateTime.now().millisecondsSinceEpoch;
        _lastEmittedPositionMs = livePos.inMilliseconds;
        _setPosition(livePos);
      }
    }
  }

  Duration get duration => _player?.state.duration ?? _state.duration;
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

  double get volume =>
      _rpcInFlight.containsKey('volume')
          ? _state.volume
          : (_player?.state.volume ?? _state.volume);
  double get rate =>
      _rpcInFlight.containsKey('rate')
          ? _state.rate
          : (_player?.state.rate ?? _state.rate);
  double get pitch =>
      _rpcInFlight.containsKey('pitch')
          ? _state.pitch
          : (_player?.state.pitch ?? _state.pitch);

  LoopMode get loopMode => _player?.state.loopMode ?? _state.loopMode;
  bool get isShuffled => _player?.state.isShuffled ?? _state.isShuffled;

  List<ma.AudioSource<AudioPlayable>> get queue =>
      _player != null ? _player!.state.queue : _state.queue;
  int get currentIndex => _player?.state.currentIndex ?? _state.currentIndex;

  bool get hasNext => _player?.state.hasNext ?? _state.hasNext;
  bool get hasPrevious => _player?.state.hasPrevious ?? _state.hasPrevious;

  CrossfadeConfig get crossfadeConfig => _player != null
      ? CrossfadeConfig(
          duration: _player!.state.crossfadeConfig.autoDuration,
          manualDuration: _player!.state.crossfadeConfig.manualDuration,
          curve: _player!.state.crossfadeConfig.curve,
        )
      : _state.crossfadeConfig;

  bool get isCrossfading => _player?.state.isCrossfading ?? false;

  bool get skipSilence => _player?.state.skipSilence ?? _state.skipSilence;
  ma.SilenceSkipMode get silenceSkipMode =>
      _player?.state.silenceSkipMode ?? _state.silenceSkipMode;
  bool get volumeNormalization =>
      _player?.state.volumeNormalization ?? _state.volumeNormalization;
  ma.ReplayGainMode get replayGainMode =>
      _player?.state.replayGainMode ?? _state.replayGainMode;
  double get preampDb => _player?.state.preamp ?? _state.preampDb;
  double get balance => _player?.state.balance ?? _state.balance;
  double get spatializerWidth =>
      _player?.state.spatializerWidth ?? _state.spatializerWidth;
  bool get mono => _player?.state.mono ?? _state.mono;
  ma.Crossfeed get crossfeed => _player?.state.crossfeed ?? _state.crossfeed;
  bool get limiterEnabled =>
      _player?.state.limiterEnabled ?? _state.limiterEnabled;
  ma.Reverb get reverb => _player?.state.reverb ?? ma.Reverb.off;

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
    final canonicalTracks = [
      for (final t in tracks) _canonicalPlayable(t),
    ];
    final items = [for (final t in canonicalTracks) t.toAudioSource()];
    final int targetIdx = (startIndex != null &&
            startIndex >= 0 &&
            startIndex < canonicalTracks.length)
        ? startIndex
        : 0;
    await _ensureMetadataEnabledFor(canonicalTracks[targetIdx]);
    await player.action.setQueue(items);
    if (play) {
      await player.action.play(position: startIndex, shuffled: shuffle);
    } else if (shuffle) {
      await player.action.setShuffle(true);
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
      final item = _canonicalPlayable(track).toAudioSource();
      await player.action.insertNext(item);
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
        for (final t in tracks) _canonicalPlayable(t).toAudioSource(),
      ];
      await player.action.append(items);
    } catch (e) {
      debugPrint('[PlaybackController] Error in appendTracks: $e');
    }
  }

  Future<void> removeFromQueue(int index) async {
    try {
      await player.action.removeAt(index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in removeFromQueue: $e');
    }
  }

  Future<void> reorderQueue(int from, int to) async {
    try {
      await player.action.reorder(from, to);
    } catch (e) {
      debugPrint('[PlaybackController] Error in reorderQueue: $e');
    }
  }

  Future<void> clearQueue() async {
    try {
      await player.action.clearQueue();
    } catch (e) {
      debugPrint('[PlaybackController] Error in clearQueue: $e');
    }
  }

  Future<void> skipToQueueIndex(int index) async {
    if (index < 0 || index >= queue.length) return;
    try {
      await _ensureMetadataEnabledFor(queue[index].data);
      await player.action.play(position: index);
    } catch (e) {
      debugPrint('[PlaybackController] Error in skipToQueueIndex: $e');
    }
  }

  ma.Equalizer get equalizer => _equalizer;
  ma.AudioDevice? get currentDevice => _currentDevice;
  List<ma.AudioDevice> get audioDevices => _audioDevices;
  Stream<List<ma.AudioDevice>> get devicesStream =>
      _injectedDevicesStream ??
      _player?.stream.globalOutputDevices ??
      const Stream.empty();

  void _applySavedDeviceIfAvailable(List<ma.AudioDevice> devices) {
    final savedId = _settingsRepository.getSettings().audioOutputDeviceId;
    if (savedId != null && savedId.isNotEmpty && _currentDevice == null) {
      final match = devices.where((d) => d.id == savedId).firstOrNull;
      if (match != null) {
        unawaited(setAudioDevice(match));
      }
    }
  }

  Future<void> setEqualizer(ma.Equalizer equalizer) async {
    _equalizer = equalizer;
    await _coalesceRpc(
      'equalizer',
      () => player.action.setEqualizer(equalizer),
    );
  }

  Future<void> setReverb(ma.Reverb reverb) async {
    await _coalesceRpc('reverb', () => player.action.setReverb(reverb));
  }

  Future<List<ma.AudioDevice>> getAudioDevices() async {
    try {
      final p = _player;
      final devices = (p != null && p.state.globalOutputDevices.isNotEmpty)
          ? p.state.globalOutputDevices
          : await ma.MiniaudioPlayer.getOutputDevices();
      if (!_isDisposed && devices.isNotEmpty) {
        _audioDevices = devices;
        _applySavedDeviceIfAvailable(devices);
        _emitScoped([_devicesNotifier]);
      }
      return devices;
    } catch (e) {
      debugPrint('[PlaybackController] getAudioDevices error: $e');
      return const [];
    }
  }

  Future<bool> setAudioDevice(ma.AudioDevice device) async {
    _currentDevice = device;
    _emitScoped([_devicesNotifier]);
    try {
      final id = device.isAuto ? 'AUTO' : device.id;
      await player.action.setOutputs({ma.AudioOutput(deviceId: id)});
      return true;
    } catch (e) {
      debugPrint('[PlaybackController] setAudioDevice error: $e');
      return false;
    }
  }

  bool get pauseOnDeviceChange => _pauseOnDeviceChange;

  Future<void> setPauseOnDeviceChange(bool pause) async {
    _pauseOnDeviceChange = pause;
    if (_player != null) {
      try {
        await _player!.action.setPauseOnDeviceChange(pause);
      } catch (e) {
        debugPrint('[PlaybackController] setPauseOnDeviceChange error: $e');
      }
    }
  }

  bool get isInfiniteMixEnabled => _isInfiniteMixEnabled;

  void setInfiniteMix(bool enabled) {
    _isInfiniteMixEnabled = enabled;
    _state = _state.copyWith(isInfiniteMixEnabled: enabled);
    _emitScoped([_controlsNotifier, _queueNotifier]);
    try {
      unawaited(
        player.action
            .setInfiniteMix(
              ma.InfiniteMixConfig(
                enabled: enabled,
                remainingTracksThreshold: 3,
              ),
            )
            .catchError((Object e) {
              debugPrint('[PlaybackController] setInfiniteMix error: $e');
            }),
      );
    } catch (e) {
      debugPrint('[PlaybackController] setInfiniteMix error: $e');
    }
  }

  void toggleInfiniteMix() {
    setInfiniteMix(!isInfiniteMixEnabled);
  }

  // ---------------------------------------------------------------------------
  // Transport Controls
  // ---------------------------------------------------------------------------
  Future<void> play() async {
    try {
      await player.action.play();
    } catch (e) {
      debugPrint('[PlaybackController] play error: $e');
    }
  }

  Future<void> pause() async {
    try {
      await player.action.pause();
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
      _wasPlayingBeforeStop = false;
      await player.action.stop();
    } catch (e) {
      debugPrint('[PlaybackController] stop error: $e');
    }
  }

  Future<void> next() async {
    try {
      await player.action.next();
    } catch (e) {
      debugPrint('[PlaybackController] next error: $e');
    }
  }

  Future<void> previous() async {
    try {
      await player.action.previous();
    } catch (e) {
      debugPrint('[PlaybackController] previous error: $e');
    }
  }

  Future<void> seek(Duration pos) async {
    try {
      _setPosition(pos);
      await _coalesceRpc('seek', () => player.action.seek(pos));
    } catch (e) {
      debugPrint('[PlaybackController] seek error: $e');
    }
  }

  Future<void> setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 2.0);
    _state = _state.copyWith(volume: clamped);
    _volumeNotifier.value = clamped;
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('volume', () => player.action.setVolume(clamped));
  }

  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(
      AppDefaults.playbackRateMin,
      AppDefaults.playbackRateMax,
    );
    _state = _state.copyWith(rate: clamped);
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('rate', () => player.action.setRate(clamped));
  }

  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(
      AppDefaults.playbackPitchMin,
      AppDefaults.playbackPitchMax,
    );
    _state = _state.copyWith(pitch: clamped);
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('pitch', () => player.action.setPitch(clamped));
  }

  Future<void> setShuffle(bool enabled) async {
    try {
      await player.action.setShuffle(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setShuffle error: $e');
    }
  }

  Future<void> toggleShuffle() => setShuffle(!isShuffled);

  Future<void> setLoopMode(LoopMode loop) async {
    try {
      await player.action.setLoopMode(loop);
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
    await _coalesceRpc(
      'crossfade',
      () => player.action.setCrossfade(
        ma.CrossfadeConfig(
          autoDuration: config.duration,
          manualDuration: config.manualDuration,
          curve: config.curve,
        ),
      ),
    );
  }

  Future<void> setSilenceConfig(ma.SilenceSkipConfig config) async {
    final validated = config.validated();
    _state = _state.copyWith(
      skipSilence: validated.enabled,
      silenceSkipMode: validated.mode,
    );
    await _coalesceRpc('silence', () => player.action.setSilenceConfig(validated));
  }

  Future<void> setSkipSilence(
    bool enabled, {
    ma.SilenceSkipMode mode = ma.SilenceSkipMode.all,
  }) async {
    final effectiveMode =
        mode == ma.SilenceSkipMode.disabled ? ma.SilenceSkipMode.all : mode;
    final config = enabled
        ? ma.SilenceSkipConfig(enabled: true, mode: effectiveMode)
        : const ma.SilenceSkipConfig.off();
    await setSilenceConfig(config);
  }

  Future<void> setReplayGainMode(ma.ReplayGainMode mode) async {
    _state = _state.copyWith(
      volumeNormalization: mode != ma.ReplayGainMode.disabled,
      replayGainMode: mode,
    );
    await _coalesceRpc(
      'replayGainMode',
      () => player.action.setReplayGainMode(mode),
    );
  }

  Future<void> setVolumeNormalization(bool enabled) async {
    await setReplayGainMode(
      enabled ? ma.ReplayGainMode.track : ma.ReplayGainMode.disabled,
    );
  }

  Future<void> setPreamp(double preampDb) async {
    _state = _state.copyWith(preampDb: preampDb);
    await _coalesceRpc('preamp', () => player.action.setPreamp(preampDb));
  }

  Future<void> setBalance(double balance) async {
    _state = _state.copyWith(balance: balance);
    await _coalesceRpc('balance', () => player.action.setBalance(balance));
  }

  Future<void> setMono(bool enabled) async {
    _state = _state.copyWith(mono: enabled);
    try {
      await player.action.setMono(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setMono error: $e');
    }
  }

  Future<void> setCrossfeed(ma.Crossfeed crossfeed) async {
    _state = _state.copyWith(crossfeed: crossfeed);
    await _coalesceRpc(
      'crossfeed',
      () => player.action.setCrossfeed(crossfeed),
    );
  }

  Future<void> setSpatializer(double width) async {
    _state = _state.copyWith(spatializerWidth: width);
    await _coalesceRpc(
      'spatializer',
      () => player.action.setSpatializer(enabled: width != 1.0, width: width),
    );
  }

  Future<void> setLimiter(bool enabled) async {
    _state = _state.copyWith(limiterEnabled: enabled);
    try {
      await player.action.setLimiter(enabled);
    } catch (e) {
      debugPrint('[PlaybackController] setLimiter error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // History Logging & State Persistence Helpers
  // ---------------------------------------------------------------------------
  void _checkHistoryLogging(PlaybackState newState) {
    final track = currentTrack ?? newState.currentTrack;
    final currentFilePath = track?.filePath;
    if (currentFilePath != _currentlyLoggedHistoryFilePath) {
      _currentlyLoggedHistoryFilePath = currentFilePath;
      _historyLoggedForCurrentTrack = false;
    }

    if (!_historyLoggedForCurrentTrack && track != null) {
      final hasPlayedThreshold =
          newState.position.inSeconds > 15 ||
          (newState.duration.inMilliseconds > 0 && newState.progress >= 0.5);

      if (hasPlayedThreshold) {
        _historyLoggedForCurrentTrack = true;
        final trackId = track.id;
        if (trackId != null && trackId > 0 && !track.isMetadataPending) {
          _store
              ?.addTracksToPlaylistInStore(LibraryStore.historyPlaylistId, [
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
    if (_isDisposed) return;
    if (!_inScopedNotify) {
      _volumeNotifier.value = volume;
      _trackNotifier.notify();
      _transportNotifier.notify();
      _controlsNotifier.notify();
      _tuningNotifier.notify();
      _queueNotifier.notify();
      _devicesNotifier.notify();
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _store?.removeListener(_onLibraryStoreUpdated);
    _scanProgressSubscription?.cancel();
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
    if (_ownsEngine && _player != null) {
      unawaited(_player!.dispose());
    }
    _trackNotifier.dispose();
    _transportNotifier.dispose();
    _controlsNotifier.dispose();
    _tuningNotifier.dispose();
    _queueNotifier.dispose();
    _devicesNotifier.dispose();
    _volumeNotifier.dispose();
    _positionNotifier.dispose();
    _positionSecondsNotifier.dispose();
    _bufferNotifier.dispose();
    _visualizerDataNotifier.dispose();
    _liveMetadataNotifier.dispose();
    _audioInfoNotifier.dispose();
    _silenceSavedDurationNotifier.dispose();
    _errorsController.close();
    super.dispose();
  }
}
