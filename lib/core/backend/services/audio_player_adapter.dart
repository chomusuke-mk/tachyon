import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

// ============================================================================
// AUDIO PLAYER ADAPTER
// ============================================================================
class AudioPlayerAdapter {
  late final int? _bufferSize;
  MiniaudioPlayer? _player;
  bool _isDisposed = false;

  double _volume = 100.0;
  double _rate = 1.0;
  double _pitch = 1.0;
  Equalizer _equalizer = Equalizer.flat;
  Reverb _reverb = Reverb.off;
  AudioDevice _audioDevice = AudioDevice.auto;
  bool _skipSilence = false;
  ReplayGainConfig _replayGain = const ReplayGainConfig();
  bool _hasReplayGain = false;
  double _preampDb = 0.0;
  double _balance = 0.0;
  bool _mono = false;
  CrossfeedMode _crossfeed = CrossfeedMode.off;
  double _spatializerWidth = 1.0;
  bool _limiterEnabled = true;
  bool _visualizerEnabled = false;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController<Duration?>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _bufferingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<VisualizerData> _visualizerController =
      StreamController<VisualizerData>.broadcast();
  final List<StreamSubscription<dynamic>> _playerSubs = [];

  AudioPlayerAdapter({int? bufferSize}) {
    _bufferSize = bufferSize;
  }

  // TODO: verificar en la siguiente actualizacion de miniaudio_player
  // (seguimiento de posicion y cursor al aplicar time-stretching con rate != 1.0x).

  /// Ensures native miniaudio_player platform bindings are initialized once.
  static Future<void> ensureInitialized({
    MiniaudioLogLevel logLevel = MiniaudioLogLevel.warning,
  }) async {
    MiniaudioPlayer.config(logLevel: logLevel);
  }

  Future<MiniaudioPlayer> _ensurePlayer() async {
    final existing = _player;
    if (existing != null) return existing;

    final p = MiniaudioPlayer(
      bufferSize: _bufferSize,
      defaultAudioDevice: _audioDevice,
    );
    _player = p;

    _playerSubs.add(
      p.stream.position.listen((v) {
        if (!_positionController.isClosed) {
          _positionController.add(v);
        }
      }),
    );
    _playerSubs.add(
      p.stream.duration.listen((v) {
        if (!_durationController.isClosed) _durationController.add(v);
      }),
    );
    _playerSubs.add(
      p.stream.playing.listen((v) {
        if (!_playingController.isClosed) _playingController.add(v);
      }),
    );
    _playerSubs.add(
      p.stream.buffering.listen((v) {
        if (!_bufferingController.isClosed) _bufferingController.add(v);
      }),
    );
    _playerSubs.add(
      p.stream.completed.listen((v) {
        if (!_completedController.isClosed) _completedController.add(v);
      }),
    );
    _playerSubs.add(
      p.stream.visualizer.listen((v) {
        if (!_visualizerController.isClosed) _visualizerController.add(v);
      }),
    );

    p.setManualVisualizerEnabled(_visualizerEnabled);
    try {
      await p.action.setVolume(_volume / 100.0);
      if (_rate != 1.0) await p.action.setRate(_rate);
      if (_pitch != 1.0) await p.action.setPitch(_pitch);
      if (_equalizer != Equalizer.flat) await p.action.setEqualizer(_equalizer);
      if (_reverb != Reverb.off) await p.action.setReverb(_reverb);
      if (_skipSilence) {
        await p.action.setSkipSilence(true, mode: SilenceSkipMode.all);
      }
      if (_hasReplayGain) {
        await p.action.setReplayGain(
          gainDb: _replayGain.gainDb,
          peak: _replayGain.peak,
          preampDb: _replayGain.preampDb,
          preventClipping: _replayGain.preventClipping,
        );
      }
      if (_preampDb != 0.0) await p.action.setPreamp(_preampDb);
      if (_balance != 0.0) await p.action.setBalance(_balance);
      if (_mono) await p.action.setMono(true);
      if (_crossfeed != CrossfeedMode.off) {
        await p.action.setCrossfeed(_crossfeed);
      }
      if ((_spatializerWidth - 1.0).abs() > 0.01) {
        await p.action.setSpatializer(enabled: true, width: _spatializerWidth);
      }
      if (!_limiterEnabled) await p.action.setLimiter(false);
    } catch (_) {}

    return p;
  }

  /// Prepares and opens an audio file by its filesystem [filePath].
  Future<void> open(String filePath, {bool play = true}) async {
    final path = _normalizePath(filePath);
    final p = await _ensurePlayer();
    await p.action.open(path, autoPlay: play);
  }

  static String _normalizePath(String filePath) {
    if (filePath.startsWith('file://')) {
      return Uri.parse(filePath).toFilePath();
    }
    return filePath;
  }

  Future<void> play() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.action.play();
    } catch (_) {}
  }

  Future<void> pause() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.action.pause();
    } catch (_) {}
  }

  Future<void> stop() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.action.stop();
    } catch (_) {}
  }

  Future<void> seek(Duration position) async {
    final p = _player;
    if (p == null) return;
    try {
      await p.action.seek(position);
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    _volume = volume;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setVolume(volume / 100.0);
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    _rate = rate;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setRate(rate);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    _pitch = pitch;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setPitch(pitch);
    } catch (_) {}
  }

  Future<void> setEqualizer(Equalizer equalizer) async {
    _equalizer = equalizer;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setEqualizer(equalizer);
    } catch (_) {}
  }

  Future<bool> setDevice(AudioDevice device) async {
    _audioDevice = device;
    final p = _player;
    if (p == null) return true;
    try {
      return await p.setDevice(device);
    } catch (_) {
      return false;
    }
  }

  Future<List<AudioDevice>> getAudioDevices() =>
      MiniaudioPlayer.getAudioDevices();

  List<AudioDevice> getAudioDevicesSync() =>
      MiniaudioPlayer.getAudioDevicesSync();

  Stream<List<AudioDevice>> get devicesStream =>
      MiniaudioPlayer.getAudioDevicesStream();

  Future<void> setSkipSilence(bool enabled) async {
    _skipSilence = enabled;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setSkipSilence(enabled, mode: SilenceSkipMode.all);
    } catch (_) {}
  }

  Future<void> setReplayGain({
    double? gainDb,
    double? peak,
    double? preampDb,
    bool? preventClipping,
  }) async {
    _hasReplayGain = true;
    _replayGain = ReplayGainConfig(
      gainDb: gainDb ?? 0.0,
      peak: peak ?? 0.0,
      preampDb: preampDb ?? 0.0,
      preventClipping: preventClipping ?? true,
    );
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setReplayGain(
        gainDb: _replayGain.gainDb,
        peak: _replayGain.peak,
        preampDb: _replayGain.preampDb,
        preventClipping: _replayGain.preventClipping,
      );
    } catch (_) {}
  }

  Future<void> clearReplayGain() async {
    _hasReplayGain = false;
    _replayGain = const ReplayGainConfig();
    final p = _player;
    if (p == null) return;
    try {
      await p.action.clearReplayGain();
    } catch (_) {}
  }

  Future<void> setPreamp(double preampDb) async {
    _preampDb = preampDb;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setPreamp(preampDb);
    } catch (_) {}
  }

  Future<void> setBalance(double balance) async {
    _balance = balance;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setBalance(balance);
    } catch (_) {}
  }

  Future<void> setMono(bool enabled) async {
    _mono = enabled;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setMono(enabled);
    } catch (_) {}
  }

  Future<void> setCrossfeed(CrossfeedMode mode) async {
    _crossfeed = mode;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setCrossfeed(mode);
    } catch (_) {}
  }

  Future<void> setSpatializer(double width) async {
    _spatializerWidth = width;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setSpatializer(
        enabled: (width - 1.0).abs() > 0.01,
        width: width,
      );
    } catch (_) {}
  }

  Future<void> setLimiter(bool enabled) async {
    _limiterEnabled = enabled;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setLimiter(enabled);
    } catch (_) {}
  }

  Future<void> setReverb(Reverb config) async {
    _reverb = config;
    final p = _player;
    if (p == null) return;
    try {
      await p.action.setReverb(config);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _isDisposed = true;
    for (final sub in _playerSubs) {
      await sub.cancel();
    }
    _playerSubs.clear();
    final p = _player;
    _player = null;
    if (p != null) {
      await p.dispose();
    }
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _bufferingController.close();
    await _completedController.close();
    await _visualizerController.close();
  }

  Stream<Duration> get positionStream => _positionController.stream;

  Stream<Duration?> get durationStream => _durationController.stream;

  Stream<bool> get playingStream => _playingController.stream;

  Stream<bool> get bufferingStream => _bufferingController.stream;

  Stream<bool> get completedStream => _completedController.stream;

  Stream<double> get volumeStream =>
      _player?.stream.volume.map((v) => v * 100.0) ?? const Stream.empty();

  Stream<double> get rateStream => _player?.stream.rate ?? const Stream.empty();

  Stream<double> get pitchStream =>
      _player?.stream.pitch ?? const Stream.empty();

  Stream<Equalizer> get equalizerStream =>
      _player?.stream.equalizer ?? const Stream.empty();

  Stream<Reverb> get reverbStream =>
      _player?.stream.reverb ?? const Stream.empty();

  Stream<AudioDevice> get audioDeviceStream =>
      _player?.stream.audioDevice ?? const Stream.empty();

  Stream<bool> get skipSilenceStream =>
      _player?.stream.skipSilence ?? const Stream.empty();

  Stream<int> get audioBitrateStream =>
      _player?.stream.audioBitrate ?? const Stream.empty();

  Stream<VisualizerData> get visualizerStream => _visualizerController.stream;

  Duration get position => _player?.state.position ?? Duration.zero;

  Duration get duration => _player?.state.duration ?? Duration.zero;

  bool get isPlaying => _player?.state.playing ?? false;

  bool get isBuffering => _player?.state.buffering ?? false;

  bool get isCompleted => _player?.state.completed ?? false;

  double get volume =>
      _player != null ? _player!.state.volume * 100.0 : _volume;

  double get rate => _player?.state.rate ?? _rate;

  double get pitch => _player?.state.pitch ?? _pitch;

  Equalizer get equalizer => _player?.state.equalizer ?? _equalizer;

  Reverb get reverb => _player?.state.reverb ?? _reverb;

  AudioDevice get audioDevice => _player?.state.audioDevice ?? _audioDevice;

  bool get skipSilence => _player?.state.skipSilence ?? _skipSilence;

  int get audioBitrate => _player?.state.audioBitrate ?? 0;

  VisualizerData get visualizer =>
      _player?.state.visualizer ?? VisualizerData.empty();

  ReplayGainConfig get replayGain => _player?.state.replayGain ?? _replayGain;

  double get preampDb => _player?.state.preampDb ?? _preampDb;

  double get balance => _player?.state.balance ?? _balance;

  bool get mono => _player?.state.mono ?? _mono;

  CrossfeedMode get crossfeed => _player?.state.crossfeed ?? _crossfeed;

  double get spatializerWidth =>
      _player?.state.spatializerWidth ?? _spatializerWidth;

  bool get limiterEnabled => _player?.state.limiterEnabled ?? _limiterEnabled;

  bool get isDisposed => _isDisposed;

  void setVisualizerEnabled(bool enabled) {
    _visualizerEnabled = enabled;
    if (!_isDisposed) {
      _player?.setManualVisualizerEnabled(enabled);
    }
  }
}
