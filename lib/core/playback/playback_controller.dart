// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
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

part 'playback_controller_dsp.dart';
part 'playback_controller_queue.dart';

class _DomainNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Shared backing state and engine bindings for [PlaybackController] mixins.
abstract class _PlaybackControllerState extends ChangeNotifier {
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
  AppLifecycleMode _lifecycleMode = AppLifecycleMode.active;
  bool _pauseOnDeviceChange = true;
  bool _wasPlayingBeforeStop = false;
  bool _isLibraryScanActive = false;
  bool _visualizerEnabled = false;
  Track? _lastCanonicalCurrentTrack;
  int _lastPositionEmitTimestamp = 0;
  int _lastEmittedPositionMs = -1;
  int _lastSystemPositionTimestamp = 0;
  int _lastSystemPositionMs = -1;

  final _DomainNotifier _trackNotifier = _DomainNotifier();
  final _DomainNotifier _transportNotifier = _DomainNotifier();
  final _DomainNotifier _controlsNotifier = _DomainNotifier();
  final _DomainNotifier _tuningNotifier = _DomainNotifier();
  final _DomainNotifier _queueNotifier = _DomainNotifier();
  final _DomainNotifier _devicesNotifier = _DomainNotifier();
  final Set<_DomainNotifier> _dirtyDomains = <_DomainNotifier>{};

  final ValueNotifier<double> _volumeNotifier = ValueNotifier<double>(1.0);
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );
  final ValueNotifier<int> _positionSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<Duration> _systemPositionNotifier =
      ValueNotifier<Duration>(Duration.zero);
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

  final Map<String, Future<void>> _rpcInFlight = {};
  final Map<String, Future<void> Function()> _rpcPending = {};

  DateTime? _lastPersistenceTime;
  String? _lastPersistedFilePath;
  int? _lastPersistedPositionMs;
  static const Duration _persistenceThrottle = Duration(seconds: 5);

  bool _isDisposed = false;
  bool _inScopedNotify = false;
  String? _currentlyLoggedHistoryFilePath;
  bool _historyLoggedForCurrentTrack = false;
  String? _lastActivePlayableKey;

  _PlaybackControllerState({
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
        (this as PlaybackController).setLibraryAnalysisActive(
          progress.isRunning,
        );
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

  /// Lazily instantiated native audio player engine handle.
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

  bool get _isUiSuppressed => _lifecycleMode != AppLifecycleMode.active;

  void _emitScoped(List<_DomainNotifier> domains) {
    if (_isDisposed) return;
    if (_isUiSuppressed) {
      _dirtyDomains.addAll(domains);
    } else {
      for (final d in domains) {
        d.notify();
      }
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
      player.action.setVisualizerEnabled(
        _visualizerEnabled && !_isUiSuppressed,
      ),
    );
    _syncSnapshotFromEngine(player, notifyAll: true);
    _isInfiniteMixEnabled = player.state.infiniteMixEnabled;
    _setPosition(player.state.position);
    _setSystemPosition(player.state.position);
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
        final cur = (this as PlaybackController).currentPlayable;
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
        if (!_isUiSuppressed) {
          _bufferNotifier.value = buf;
        } else {
          _dirtyDomains.add(_transportNotifier);
        }
        if (_state.isBuffering != buf.isBuffering) {
          _state = _state.copyWith(isBuffering: buf.isBuffering);
          _emitScoped([_transportNotifier]);
        }
      }),
      player.stream.metadata.listen((meta) {
        if (_isDisposed) return;
        final playable = (this as PlaybackController).currentPlayable;
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
        final playable = (this as PlaybackController).currentPlayable;
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
        if (_isDisposed || _isUiSuppressed) return;
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

      // Always keep system notification progress updated (~2s cadence or seek jump).
      final sysDeltaMs = now - _lastSystemPositionTimestamp;
      if (sysDeltaMs >= 2000 ||
          (pos.inMilliseconds - _lastSystemPositionMs).abs() > 2000) {
        _lastSystemPositionTimestamp = now;
        _lastSystemPositionMs = pos.inMilliseconds;
        _setSystemPosition(pos);
      }

      if (!_isUiSuppressed) {
        final uiDeltaMs = now - _lastPositionEmitTimestamp;
        if (uiDeltaMs >= 33 ||
            (pos.inMilliseconds - _lastEmittedPositionMs).abs() > 1000) {
          _lastPositionEmitTimestamp = now;
          _lastEmittedPositionMs = pos.inMilliseconds;
          _setPosition(pos);
        }
      }

      if ((pos.inMilliseconds - _state.position.inMilliseconds).abs() >= 1000) {
        final oldState = _state;
        _state = _state.copyWith(position: pos);
        _checkHistoryLogging(_state);
        _checkStatePersistence(oldState, _state);
      }
    });

    _visualizerSubscription = player.stream.visualizer.listen((vis) {
      if (!_visualizerEnabled || _isUiSuppressed || _isDisposed) return;
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

  void _setSystemPosition(Duration pos) {
    if (_systemPositionNotifier.value != pos) {
      _systemPositionNotifier.value = pos;
    }
  }

  bool _shouldEnableMetadataFor(AudioPlayable? playable) {
    if (playable?.isStream == true) return true;
    return _isLibraryScanActive;
  }

  void _syncMetadataEnabled() {
    final p = _player;
    if (p == null || _isDisposed) return;
    final wantMetadata = _shouldEnableMetadataFor(
      (this as PlaybackController).currentPlayable,
    );
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
    final ctrl = this as PlaybackController;

    final cur = ctrl.currentTrack;
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

    if (ctrl.queue.isNotEmpty) {
      var queueUpgraded = false;
      for (final item in ctrl.queue) {
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

  void _applySavedDeviceIfAvailable(List<ma.AudioDevice> devices) {
    final savedId = _settingsRepository.getSettings().audioOutputDeviceId;
    if (savedId != null && savedId.isNotEmpty && _currentDevice == null) {
      final match = devices.where((d) => d.id == savedId).firstOrNull;
      if (match != null) {
        unawaited((this as PlaybackController).setAudioDevice(match));
      }
    }
  }

  void _checkHistoryLogging(PlaybackState newState) {
    final track = (this as PlaybackController).currentTrack ?? newState.currentTrack;
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

  Future<void> _flushStatePersistence(String filePath, int positionMs) async {
    _lastPersistenceTime = DateTime.now();
    _lastPersistedFilePath = filePath;
    _lastPersistedPositionMs = positionMs;

    await _settingsRepository.setLastPlayed(
      filePath: filePath,
      positionMs: positionMs,
    );
  }
}

/// Coordinates audio playback, queue management, DSP effects, live stream
/// metadata, scoped UI listenables, and lifecycle-aware UI update throttling.
class PlaybackController extends _PlaybackControllerState
    with _PlaybackControllerQueueMixin, _PlaybackControllerDspMixin {
  /// Creates a [PlaybackController] backed by [settingsRepository] and optional
  /// [store], [metadataService], [engine], and [devicesStream].
  PlaybackController({
    super.store,
    required super.settingsRepository,
    super.metadataService,
    super.engine,
    super.devicesStream,
  });

  /// Last file path written by playback position persistence (exposed for tests).
  @visibleForTesting
  String? get lastPersistedFilePath => _lastPersistedFilePath;

  /// Last position in milliseconds persisted to settings (exposed for tests).
  @visibleForTesting
  int? get lastPersistedPositionMs => _lastPersistedPositionMs;

  /// Scoped listenable triggered when active track metadata changes.
  Listenable get trackListenable => _trackNotifier;

  /// Scoped listenable triggered when play/pause/buffer/completion state changes.
  Listenable get transportListenable => _transportNotifier;

  /// Scoped listenable triggered when shuffle, loop, or crossfade flags change.
  Listenable get controlsListenable => _controlsNotifier;

  /// Reactive volume level listenable (`0.0` to `2.0`).
  ValueListenable<double> get volumeListenable => _volumeNotifier;

  /// Scoped listenable triggered when DSP tuning parameters change.
  Listenable get tuningListenable => _tuningNotifier;

  /// Scoped listenable triggered when queue contents or active index change.
  Listenable get queueListenable => _queueNotifier;

  /// Scoped listenable triggered when available audio output devices change.
  Listenable get devicesListenable => _devicesNotifier;

  /// Mutable UI position notifier (paused when lifecycle is suspended/background).
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;

  /// Read-only UI position listenable (paused when lifecycle is suspended/background).
  ValueListenable<Duration> get positionListenable => _positionNotifier;

  /// Integer second position listenable for minimal digital clock rebuilds.
  ValueListenable<int> get positionSecondsListenable =>
      _positionSecondsNotifier;

  /// System media position listenable that keeps updating during suspended and
  /// background modes for OS media notifications (Android, MPRIS, SMTC).
  ValueListenable<Duration> get systemPositionListenable =>
      _systemPositionNotifier;

  /// Stream/file buffer range listenable.
  ValueListenable<ma.Buffer> get bufferListenable => _bufferNotifier;

  /// Real-time FFT/PCM visualizer sample listenable.
  ValueListenable<ma.VisualizerData> get visualizerDataListenable =>
      _visualizerDataNotifier;

  /// Live ICY / stream metadata listenable.
  ValueListenable<ma.AudioMetadata?> get liveMetadataListenable =>
      _liveMetadataNotifier;

  /// Live audio stream format info (sample rate, channels, bitrate).
  ValueListenable<ma.AudioInfo?> get audioInfoListenable => _audioInfoNotifier;

  /// Cumulative silence duration skipped during playback.
  ValueListenable<Duration> get silenceSavedDurationListenable =>
      _silenceSavedDurationNotifier;

  /// Broadcast stream of fatal or recoverable engine exceptions.
  Stream<ma.MiniaudioPlayerException> get errorsStream =>
      _errorsController.stream;

  /// Whether a background library scan is currently running.
  bool get isLibraryAnalysisActive => _isLibraryScanActive;

  /// Current [AppLifecycleMode] controlling UI emission throttling.
  AppLifecycleMode get lifecycleMode => _lifecycleMode;

  /// Updates whether library analysis metadata enrichment is active.
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

  /// Resolves [playable] to its canonical in-memory [Track] instance if indexed.
  AudioPlayable resolvePlayable(AudioPlayable playable) =>
      _canonicalPlayable(playable);

  /// Resolved display metadata merging persisted tags and live stream updates.
  ResolvedPlaybackMetadata? get currentDisplayMetadata {
    final playable = currentPlayable;
    if (playable == null) return null;
    return ResolvedPlaybackMetadata.resolve(
      playable: playable,
      liveMetadata: _liveMetadataNotifier.value,
      liveAudioInfo: _audioInfoNotifier.value,
    );
  }

  /// Latest combined [PlaybackState] snapshot.
  PlaybackState get state => _state;

  /// Currently loaded queue entry in the player engine, if any.
  ma.AudioSource<AudioPlayable>? get currentEntry =>
      _player != null ? _player!.state.currentItem : _state.currentEntry;

  /// Currently playing or queued [AudioPlayable], resolved canonically.
  AudioPlayable? get currentPlayable {
    final raw = currentEntry?.data ?? _state.currentPlayable ?? currentTrack;
    if (raw == null) return null;
    return _canonicalPlayable(raw);
  }

  /// Currently active [Track], or `null` when idle or playing a non-track stream.
  Track? get currentTrack {
    final raw =
        currentEntry?.data ?? _state.currentPlayable ?? _state.currentTrack;
    if (raw is Track) {
      final canonical = _canonicalPlayable(raw);
      return canonical is Track ? canonical : raw;
    }
    return null;
  }

  /// Returns `true` when [track] matches the active track by reference, ID, or path.
  bool isCurrentTrack(Track? track) {
    final cur = currentTrack;
    return track != null &&
        (cur == track ||
            (cur?.id != null && cur?.id == track.id) ||
            (cur?.filePath.isNotEmpty == true &&
                cur?.filePath == track.filePath));
  }

  /// Whether audio is currently playing.
  bool get isPlaying => _player?.state.isPlaying ?? _state.isPlaying;

  /// Whether the player engine is currently buffering stream data.
  bool get isBuffering => _player?.state.isBuffering ?? _state.isBuffering;

  /// Whether the active queue finished playing naturally.
  bool get isCompleted => _state.isCompleted;

  /// Whether the current playable is a live audio stream without finite duration.
  bool get isLiveStream =>
      currentPlayable?.isStream ??
      (_player != null &&
          _player!.state.currentItem != null &&
          _player!.state.duration == null) ||
      _state.isLiveStream;

  /// Current playback position exposed to UI listeners.
  Duration get position => _positionNotifier.value;

  /// Current stream buffer bounds.
  ma.Buffer get buffer => _bufferNotifier.value;

  /// Latest live ICY/stream metadata frame.
  ma.AudioMetadata? get liveMetadata => _liveMetadataNotifier.value;

  /// Latest live audio format details.
  ma.AudioInfo? get liveAudioInfo => _audioInfoNotifier.value;

  /// Total duration skipped by silence removal.
  Duration get silenceSavedDuration => _silenceSavedDurationNotifier.value;

  /// Total duration of the current track, or [Duration.zero] for live streams.
  Duration get duration => _player?.state.duration ?? _state.duration;

  /// Normalized playback progress in `[0.0, 1.0]`.
  double get progress => duration.inMilliseconds > 0
      ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  /// Remaining duration until end of the current track.
  Duration get remaining =>
      duration > position ? duration - position : Duration.zero;

  /// Normalized precomputed waveform amplitude at the current playback position.
  double get currentVisualAmplitude {
    if (!isPlaying) return 0.0;
    final track = currentTrack;
    return track?.getPointAtPosition(position, duration) ?? 0.0;
  }

  /// Enables or disables real-time audio visualizer sampling.
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
            .setVisualizerEnabled(enabled && !_isUiSuppressed)
            .catchError((_) {}),
      );
    }
  }

  /// Applies [mode] to suppress UI rebuilds/tickers while keeping OS media
  /// notifications active, and flushes pending UI state on return to active mode.
  void setLifecycleMode(AppLifecycleMode mode) {
    if (_lifecycleMode == mode) return;
    _lifecycleMode = mode;
    final suppressed = _isUiSuppressed;
    if (suppressed) {
      if (_player != null) {
        unawaited(
          _player!.action.setVisualizerEnabled(false).catchError((_) {}),
        );
      }
      _visualizerDataNotifier.value = ma.VisualizerData.empty();
      return;
    }

    if (_player != null) {
      if (_visualizerEnabled) {
        unawaited(
          _player!.action.setVisualizerEnabled(true).catchError((_) {}),
        );
      }
      final livePos = _player!.state.position;
      _lastPositionEmitTimestamp = DateTime.now().millisecondsSinceEpoch;
      _lastEmittedPositionMs = livePos.inMilliseconds;
      _setPosition(livePos);
      _setSystemPosition(livePos);
      _bufferNotifier.value = _player!.state.buffer;
      _silenceSavedDurationNotifier.value =
          _player!.state.silenceSavedDuration;
    }

    if (_dirtyDomains.isNotEmpty) {
      final domains = _dirtyDomains.toList(growable: false);
      _dirtyDomains.clear();
      _emitScoped(domains);
    }
  }

  /// Legacy helper mapping [minimized] to [AppLifecycleMode.suspended] or
  /// [AppLifecycleMode.active].
  void setMinimized(bool minimized) {
    setLifecycleMode(
      minimized ? AppLifecycleMode.suspended : AppLifecycleMode.active,
    );
  }

  /// Immediately persists the active track path and position to settings.
  Future<void> flushStatePersistence() async {
    final current = currentTrack;
    if (current != null) {
      await _flushStatePersistence(
        current.filePath,
        (_player?.state.position ?? _positionNotifier.value).inMilliseconds,
      );
    }
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    if (!_inScopedNotify) {
      _volumeNotifier.value = volume;
      final allDomains = <_DomainNotifier>[
        _trackNotifier,
        _transportNotifier,
        _controlsNotifier,
        _tuningNotifier,
        _queueNotifier,
        _devicesNotifier,
      ];
      if (_isUiSuppressed) {
        _dirtyDomains.addAll(allDomains);
      } else {
        for (final d in allDomains) {
          d.notify();
        }
      }
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
    _systemPositionNotifier.dispose();
    _bufferNotifier.dispose();
    _visualizerDataNotifier.dispose();
    _liveMetadataNotifier.dispose();
    _audioInfoNotifier.dispose();
    _silenceSavedDurationNotifier.dispose();
    _errorsController.close();
    super.dispose();
  }
}
