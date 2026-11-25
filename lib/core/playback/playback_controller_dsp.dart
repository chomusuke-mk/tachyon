part of 'playback_controller.dart';

mixin _PlaybackControllerDspMixin on _PlaybackControllerState {
  /// Master output volume in `[0.0, 2.0]`.
  double get volume => _rpcInFlight.containsKey('volume')
      ? _state.volume
      : (_player?.state.volume ?? _state.volume);

  /// Playback speed multiplier.
  double get rate => _rpcInFlight.containsKey('rate')
      ? _state.rate
      : (_player?.state.rate ?? _state.rate);

  /// Pitch multiplier independent of playback speed.
  double get pitch => _rpcInFlight.containsKey('pitch')
      ? _state.pitch
      : (_player?.state.pitch ?? _state.pitch);

  /// Active queue repeat mode.
  LoopMode get loopMode => _player?.state.loopMode ?? _state.loopMode;

  /// Whether queue shuffle order is active.
  bool get isShuffled => _player?.state.isShuffled ?? _state.isShuffled;

  /// Active crossfade transition configuration.
  CrossfadeConfig get crossfadeConfig => _player != null
      ? CrossfadeConfig(
          duration: _player!.state.crossfadeConfig.autoDuration,
          manualDuration: _player!.state.crossfadeConfig.manualDuration,
          curve: _player!.state.crossfadeConfig.curve,
        )
      : _state.crossfadeConfig;

  /// Whether an audio crossfade transition is currently in progress.
  bool get isCrossfading => _player?.state.isCrossfading ?? false;

  /// Whether silence skipping is enabled.
  bool get skipSilence => _player?.state.skipSilence ?? _state.skipSilence;

  /// Active silence skipping mode.
  ma.SilenceSkipMode get silenceSkipMode =>
      _player?.state.silenceSkipMode ?? _state.silenceSkipMode;

  /// Whether ReplayGain loudness normalization is enabled.
  bool get volumeNormalization =>
      _player?.state.volumeNormalization ?? _state.volumeNormalization;

  /// Active ReplayGain normalization mode.
  ma.ReplayGainMode get replayGainMode =>
      _player?.state.replayGainMode ?? _state.replayGainMode;

  /// Digital preamp gain offset in decibels.
  double get preampDb => _player?.state.preamp ?? _state.preampDb;

  /// Stereo channel balance in `[-1.0, 1.0]`.
  double get balance => _player?.state.balance ?? _state.balance;

  /// Stereo widener factor.
  double get spatializerWidth =>
      _player?.state.spatializerWidth ?? _state.spatializerWidth;

  /// Whether stereo downmix to mono is enabled.
  bool get mono => _player?.state.mono ?? _state.mono;

  /// Active Bauer crossfeed preset.
  ma.Crossfeed get crossfeed => _player?.state.crossfeed ?? _state.crossfeed;

  /// Whether the true-peak output limiter is enabled.
  bool get limiterEnabled =>
      _player?.state.limiterEnabled ?? _state.limiterEnabled;

  /// Active studio reverb configuration.
  ma.Reverb get reverb => _player?.state.reverb ?? ma.Reverb.off;

  /// Active 10-band equalizer configuration.
  ma.Equalizer get equalizer => _equalizer;

  /// Currently selected audio output device, if resolved.
  ma.AudioDevice? get currentDevice => _currentDevice;

  /// Cached list of discovered audio output devices.
  List<ma.AudioDevice> get audioDevices => _audioDevices;

  /// Broadcast stream of available audio output devices.
  Stream<List<ma.AudioDevice>> get devicesStream =>
      _injectedDevicesStream ??
      _player?.stream.globalOutputDevices ??
      const Stream.empty();

  /// Whether playback automatically pauses on audio output device changes.
  bool get pauseOnDeviceChange => _pauseOnDeviceChange;

  /// Applies [equalizer] settings to the audio engine.
  Future<void> setEqualizer(ma.Equalizer equalizer) async {
    _equalizer = equalizer;
    await _coalesceRpc(
      'equalizer',
      () => player.action.setEqualizer(equalizer),
    );
  }

  /// Applies [reverb] settings to the audio engine.
  Future<void> setReverb(ma.Reverb reverb) async {
    await _coalesceRpc('reverb', () => player.action.setReverb(reverb));
  }

  /// Queries available audio output devices and notifies device listeners.
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
      _log.e('getAudioDevices error', error: e);
      return const [];
    }
  }

  /// Routes audio output to [device] and returns whether switching succeeded.
  Future<bool> setAudioDevice(ma.AudioDevice device) async {
    _log.d('setAudioDevice id=${device.id} name="${device.name}" isAuto=${device.isAuto}');
    _currentDevice = device;
    _emitScoped([_devicesNotifier]);
    try {
      final id = device.isAuto ? 'AUTO' : device.id;
      await player.action.setOutputs({ma.AudioOutput(deviceId: id)});
      return true;
    } catch (e) {
      _log.e('setAudioDevice error', error: e);
      return false;
    }
  }

  /// Sets whether playback should automatically pause on device disconnect/change.
  Future<void> setPauseOnDeviceChange(bool pause) async {
    _pauseOnDeviceChange = pause;
    if (_player != null) {
      try {
        await _player!.action.setPauseOnDeviceChange(pause);
      } catch (e) {
        _log.e('setPauseOnDeviceChange error', error: e);
      }
    }
  }

  /// Resumes or starts playback of the current queue item.
  Future<void> play() async {
    _log.d('play requested');
    try {
      await player.action.play();
    } catch (e) {
      _log.e('play error', error: e);
    }
  }

  /// Pauses playback at the current position.
  Future<void> pause() async {
    _log.d('pause requested');
    try {
      await player.action.pause();
    } catch (e) {
      _log.e('pause error', error: e);
    }
  }

  /// Toggles between playing and paused transport states.
  Future<void> playOrPause() async {
    if ((this as PlaybackController).isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Stops playback and resets completion tracking.
  Future<void> stop() async {
    _log.d('stop requested');
    try {
      _wasPlayingBeforeStop = false;
      await player.action.stop();
    } catch (e) {
      _log.e('stop error', error: e);
    }
  }

  /// Advances playback to the next queue item.
  Future<void> next() async {
    _log.d('next requested');
    try {
      await player.action.next();
    } catch (e) {
      _log.e('next error', error: e);
    }
  }

  /// Returns playback to the previous queue item.
  Future<void> previous() async {
    _log.d('previous requested');
    try {
      await player.action.previous();
    } catch (e) {
      _log.e('previous error', error: e);
    }
  }

  /// Seeks the active track to [pos].
  Future<void> seek(Duration pos) async {
    _log.d('seek(${pos.inMilliseconds}ms, uiSuppressed=$_isUiSuppressed)');
    try {
      if (!_isUiSuppressed) {
        _setPosition(pos);
      }
      _setSystemPosition(pos);
      await _coalesceRpc('seek', () => player.action.seek(pos));
    } catch (e) {
      _log.e('seek error', error: e);
    }
  }

  /// Sets master volume to [vol] (clamped to `[0.0, 2.0]`).
  Future<void> setVolume(double vol) async {
    final clamped = vol.clamp(0.0, 2.0);
    _state = _state.copyWith(volume: clamped);
    _volumeNotifier.value = clamped;
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('volume', () => player.action.setVolume(clamped));
  }

  /// Sets playback speed multiplier to [rate].
  Future<void> setRate(double rate) async {
    final clamped = rate.clamp(
      AppDefaults.playbackRateMin,
      AppDefaults.playbackRateMax,
    );
    _state = _state.copyWith(rate: clamped);
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('rate', () => player.action.setRate(clamped));
  }

  /// Sets playback pitch multiplier to [pitch].
  Future<void> setPitch(double pitch) async {
    final clamped = pitch.clamp(
      AppDefaults.playbackPitchMin,
      AppDefaults.playbackPitchMax,
    );
    _state = _state.copyWith(pitch: clamped);
    _emitScoped([_tuningNotifier]);
    await _coalesceRpc('pitch', () => player.action.setPitch(clamped));
  }

  /// Enables or disables queue shuffle mode.
  Future<void> setShuffle(bool enabled) async {
    _log.d('setShuffle($enabled)');
    try {
      await player.action.setShuffle(enabled);
    } catch (e) {
      _log.e('setShuffle error', error: e);
    }
  }

  /// Toggles queue shuffle mode.
  Future<void> toggleShuffle() => setShuffle(!isShuffled);

  /// Sets queue repeat mode to [loop].
  Future<void> setLoopMode(LoopMode loop) async {
    _log.d('setLoopMode(${loop.name})');
    try {
      await player.action.setLoopMode(loop);
    } catch (e) {
      _log.e('setLoopMode error', error: e);
    }
  }

  /// Cycles through [LoopMode.off], [LoopMode.all], and [LoopMode.one].
  Future<void> toggleLoopMode() async {
    try {
      final nextMode = loopMode.next();
      await setLoopMode(nextMode);
    } catch (e) {
      _log.e('toggleLoopMode error', error: e);
    }
  }

  /// Configures automatic and manual crossfade settings from [config].
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

  /// Configures silence skipping using [config].
  Future<void> setSilenceConfig(ma.SilenceSkipConfig config) async {
    final validated = config.validated();
    _state = _state.copyWith(
      skipSilence: validated.enabled,
      silenceSkipMode: validated.mode,
    );
    await _coalesceRpc('silence', () => player.action.setSilenceConfig(validated));
  }

  /// Convenience helper enabling or disabling silence skipping in [mode].
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

  /// Configures ReplayGain loudness normalization [mode].
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

  /// Enables track-level ReplayGain loudness normalization when [enabled].
  Future<void> setVolumeNormalization(bool enabled) async {
    await setReplayGainMode(
      enabled ? ma.ReplayGainMode.track : ma.ReplayGainMode.disabled,
    );
  }

  /// Sets digital preamp gain to [preampDb] decibels.
  Future<void> setPreamp(double preampDb) async {
    _state = _state.copyWith(preampDb: preampDb);
    await _coalesceRpc('preamp', () => player.action.setPreamp(preampDb));
  }

  /// Sets stereo channel balance to [balance] in `[-1.0, 1.0]`.
  Future<void> setBalance(double balance) async {
    _state = _state.copyWith(balance: balance);
    await _coalesceRpc('balance', () => player.action.setBalance(balance));
  }

  /// Enables or disables stereo-to-mono downmixing.
  Future<void> setMono(bool enabled) async {
    _state = _state.copyWith(mono: enabled);
    try {
      await player.action.setMono(enabled);
    } catch (e) {
      _log.e('setMono error', error: e);
    }
  }

  /// Configures Bauer stereo-to-binaural [crossfeed] preset.
  Future<void> setCrossfeed(ma.Crossfeed crossfeed) async {
    _state = _state.copyWith(crossfeed: crossfeed);
    await _coalesceRpc(
      'crossfeed',
      () => player.action.setCrossfeed(crossfeed),
    );
  }

  /// Configures stereo field spatializer [width].
  Future<void> setSpatializer(double width) async {
    _state = _state.copyWith(spatializerWidth: width);
    await _coalesceRpc(
      'spatializer',
      () => player.action.setSpatializer(enabled: width != 1.0, width: width),
    );
  }

  /// Enables or disables the true-peak digital output limiter.
  Future<void> setLimiter(bool enabled) async {
    _state = _state.copyWith(limiterEnabled: enabled);
    try {
      await player.action.setLimiter(enabled);
    } catch (e) {
      _log.e('setLimiter error', error: e);
    }
  }
}
