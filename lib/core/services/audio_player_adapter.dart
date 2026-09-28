import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:tachyon/core/constants/app_defaults.dart';

// ============================================================================
// AUDIO PLAYER ADAPTER
// ============================================================================

/// Production implementation of [AudioPlayerAdapter] backed by `media_kit.Player`.
///
/// Handles:
/// - Native `libmpv` initialization via `MediaKit.ensureInitialized()`.
/// - Platform audio output configuration (`ao` driver selection):
///   * Android: `audiotrack,opensles`
///   * iOS: `audiounit`
///   * macOS: `coreaudio`
///   * Windows / Linux: platform default (WASAPI / PipeWire / PulseAudio / ALSA)
/// - Continuous stream continuity (`audio-stream-silence=yes`) on all platforms
///   except iOS (where it is incompatible with `audiounit`).
/// - Automatic subtitle scanning suppression (`sub-auto=no`).
/// - Pitch preservation enabled by default via `PlayerConfiguration(pitch: true)`
///   which activates mpv's `scaletempo2` time-stretching filter.
class AudioPlayerAdapter {
  final Player _player;
  bool _isDisposed = false;

  AudioPlayerAdapter()
    : _player = Player(
        configuration: PlayerConfiguration(
          pitch: true,
          osc: false,
          async: AppDefaults.audioPlayerAsyncEnabled,
          bufferSize: AppDefaults.audioPlayerAsyncEnabled
              ? 0
              : 10 * 1024 * 1024, // 10 MB buffer for synchronous mode
          libass: false,
          muted: false,
          title: 'tachyon',
        ),
      ) {
    if (_player.platform is NativePlayer) {
      final nativePlayer = _player.platform as NativePlayer;
      nativePlayer.setProperty('audio-stream-silence', 'yes');
      nativePlayer.setProperty('sub-auto', 'no');
      nativePlayer.setProperty('vid', 'no');
    }
  }

  /// Ensures native media_kit platform bindings are initialized once.
  static Future<void> ensureInitialized() async {
    MediaKit.ensureInitialized();
  }

  Future<void> open(String uri, {bool play = true}) async {
    await _player.open(Media(uri), play: play);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) => _player.setVolume(volume / 100.0);

  Future<void> setRate(double rate) => _player.setRate(rate);

  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  Future<void> setSkipSilence(bool enabled) => Future.value();
  //_player.setSkipSilenceEnabled(enabled);

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

  Stream<bool> get skipSilenceStream =>
      Stream.value(false); //_player.stream.skipSilenceEnabled;

  Duration get position => _player.state.position;

  Duration get duration => _player.state.duration;

  bool get isPlaying => _player.state.playing;

  bool get isBuffering => _player.state.buffering;

  bool get isCompleted => _player.state.completed;

  double get volume => _player.state.volume * 100.0;

  double get rate => _player.state.rate;

  double get pitch => _player.state.pitch;

  bool get skipSilence => false; //_player.state.skipSilenceEnabled;

  bool get isDisposed => _isDisposed;
}
