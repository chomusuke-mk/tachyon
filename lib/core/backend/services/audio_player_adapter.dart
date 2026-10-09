import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

// ============================================================================
// AUDIO PLAYER ADAPTER
// ============================================================================
class AudioPlayerAdapter {
  final MiniaudioPlayer _player;
  bool _isDisposed = false;

  AudioPlayerAdapter({int? bufferSize})
    : _player = MiniaudioPlayer(bufferSize: bufferSize);

  /// Ensures native miniaudio_player platform bindings are initialized once.
  static Future<void> ensureInitialized({
    MiniaudioLogLevel logLevel = MiniaudioLogLevel.warning,
  }) async {
    MiniaudioPlayer.config(logLevel: logLevel);
  }

  /// Prepares and opens an audio file by its filesystem [filePath].
  Future<void> open(String filePath, {bool play = true}) async {
    final path = _normalizePath(filePath);
    await _player.action.open(path, autoPlay: play);
  }

  static String _normalizePath(String filePath) {
    if (filePath.startsWith('file://')) {
      return Uri.parse(filePath).toFilePath();
    }
    return filePath;
  }

  Future<void> play() async {
    try {
      await _player.action.play();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _player.action.pause();
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _player.action.stop();
    } catch (_) {}
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.action.seek(position);
    } catch (_) {}
  }

  Future<void> setVolume(double volume) async {
    try {
      await _player.action.setVolume(volume / 100.0);
    } catch (_) {}
  }

  Future<void> setRate(double rate) async {
    try {
      await _player.action.setRate(rate);
    } catch (_) {}
  }

  Future<void> setPitch(double pitch) async {
    try {
      await _player.action.setPitch(pitch);
    } catch (_) {}
  }

  Future<void> setEqualizer(Equalizer equalizer) async {
    try {
      await _player.action.setEqualizer(equalizer);
    } catch (_) {}
  }

  Future<bool> setDevice(AudioDevice device) async {
    try {
      return await _player.setDevice(device);
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
    try {
      await _player.action.setSkipSilence(enabled, mode: SilenceSkipMode.all);
    } catch (_) {}
  }

  Future<void> setReplayGain({
    double? gainDb,
    double? peak,
    double? preampDb,
    bool? preventClipping,
  }) async {
    try {
      await _player.action.setReplayGain(
        gainDb: gainDb ?? 0.0,
        peak: peak ?? 0.0,
        preampDb: preampDb ?? 0.0,
        preventClipping: preventClipping ?? true,
      );
    } catch (_) {}
  }

  Future<void> clearReplayGain() async {
    try {
      await _player.action.clearReplayGain();
    } catch (_) {}
  }

  Future<void> setPreamp(double preampDb) async {
    try {
      await _player.action.setPreamp(preampDb);
    } catch (_) {}
  }

  Future<void> setBalance(double balance) async {
    try {
      await _player.action.setBalance(balance);
    } catch (_) {}
  }

  Future<void> setMono(bool enabled) async {
    try {
      await _player.action.setMono(enabled);
    } catch (_) {}
  }

  Future<void> setCrossfeed(CrossfeedMode mode) async {
    try {
      await _player.action.setCrossfeed(mode);
    } catch (_) {}
  }

  Future<void> setSpatializer(double width) async {
    try {
      await _player.action.setSpatializer(
        enabled: (width - 1.0).abs() > 0.01,
        width: width,
      );
    } catch (_) {}
  }

  Future<void> setLimiter(bool enabled) async {
    try {
      await _player.action.setLimiter(enabled);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _player.dispose();
  }

  Stream<Duration> get positionStream => _player.stream.position;

  Stream<Duration?> get durationStream => _player.stream.duration;

  Stream<bool> get playingStream => _player.stream.playing;

  Stream<bool> get bufferingStream => _player.stream.buffering;

  Stream<bool> get completedStream => _player.stream.completed;

  Stream<double> get volumeStream =>
      _player.stream.volume.map((v) => v * 100.0);

  Stream<double> get rateStream => _player.stream.rate;

  Stream<double> get pitchStream => _player.stream.pitch;

  Stream<Equalizer> get equalizerStream => _player.stream.equalizer;

  Stream<AudioDevice> get audioDeviceStream => _player.stream.audioDevice;

  Stream<bool> get skipSilenceStream => _player.stream.skipSilence;

  Stream<int> get audioBitrateStream => _player.stream.audioBitrate;

  Stream<VisualizerData> get visualizerStream => _player.stream.visualizer;

  Duration get position => _player.state.position;

  Duration get duration => _player.state.duration;

  bool get isPlaying => _player.state.playing;

  bool get isBuffering => _player.state.buffering;

  bool get isCompleted => _player.state.completed;

  double get volume => _player.state.volume * 100.0;

  double get rate => _player.state.rate;

  double get pitch => _player.state.pitch;

  Equalizer get equalizer => _player.state.equalizer;

  AudioDevice get audioDevice => _player.state.audioDevice;

  bool get skipSilence => _player.state.skipSilence;

  int get audioBitrate => _player.state.audioBitrate;

  VisualizerData get visualizer => _player.state.visualizer;

  ReplayGainConfig get replayGain => _player.state.replayGain;

  double get preampDb => _player.state.preampDb;

  double get balance => _player.state.balance;

  bool get mono => _player.state.mono;

  CrossfeedMode get crossfeed => _player.state.crossfeed;

  double get spatializerWidth => _player.state.spatializerWidth;

  bool get limiterEnabled => _player.state.limiterEnabled;

  bool get isDisposed => _isDisposed;

  void setVisualizerEnabled(bool enabled) {
    if (!_isDisposed) {
      _player.setManualVisualizerEnabled(enabled);
    }
  }
}
