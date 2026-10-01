import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

// ============================================================================
// AUDIO PLAYER ADAPTER
// ============================================================================

/// Production implementation of [AudioPlayerAdapter] backed by `miniaudio_player.MiniaudioPlayer`.
class AudioPlayerAdapter {
  final MiniaudioPlayer _player;
  bool _isDisposed = false;

  AudioPlayerAdapter({int? bufferSize})
    : _player = MiniaudioPlayer(bufferSize: bufferSize);

  /// Ensures native miniaudio_player platform bindings are initialized once.
  static Future<void> ensureInitialized({
    MiniaudioLogLevel logLevel = MiniaudioLogLevel.info,
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

  Future<void> play() => _player.action.play();

  Future<void> pause() => _player.action.pause();

  Future<void> stop() => _player.action.stop();

  Future<void> seek(Duration position) => _player.action.seek(position);

  Future<void> setVolume(double volume) =>
      _player.action.setVolume(volume / 100.0);

  Future<void> setRate(double rate) => _player.action.setRate(rate);

  Future<void> setPitch(double pitch) => _player.action.setPitch(pitch);

  Future<void> setEqualizer(Equalizer equalizer) =>
      _player.action.setEqualizer(equalizer);

  Future<bool> setDevice(AudioDevice device) => _player.setDevice(device);

  Future<List<AudioDevice>> getAudioDevices({bool includeAuto = true}) =>
      MiniaudioPlayer.getAudioDevices(includeAuto: includeAuto);

  Future<void> setSkipSilence(bool enabled) => Future.value();

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

  Stream<bool> get skipSilenceStream => Stream.value(false);

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

  bool get skipSilence => false;

  bool get isDisposed => _isDisposed;
}
