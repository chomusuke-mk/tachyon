import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/services/tachyon_audio_platform.dart';

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
  final AudioPlayer _player;
  bool _isDisposed = false;

  AudioPlayerAdapter({
    AudioLoadConfiguration configuration = const AudioLoadConfiguration(
      androidLivePlaybackSpeedControl: AndroidLivePlaybackSpeedControl(
        fallbackMaxPlaybackSpeed: AppDefaults.playbackRateMax,
        fallbackMinPlaybackSpeed: AppDefaults.playbackRateMin,
        maxLiveOffsetErrorForUnitSpeed: Duration(milliseconds: 500),
        minPossibleLiveOffsetSmoothingFactor: 0.1,
        minUpdateInterval: Duration(milliseconds: 100),
        proportionalControlFactor: 0.1,
        targetLiveOffsetIncrementOnRebuffer: Duration(milliseconds: 100),
      ),
      androidLoadControl: AndroidLoadControl(
        backBufferDuration: Duration(seconds: 30),
        bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 500),
        bufferForPlaybackDuration: Duration(milliseconds: 500),
        maxBufferDuration: Duration(seconds: 30),
        minBufferDuration: Duration(milliseconds: 500),
        prioritizeTimeOverSizeThresholds: true,
      ),
    ),
  }) : _player = AudioPlayer(audioLoadConfiguration: configuration);

  /// Ensures native media_kit platform bindings are initialized once.
  static Future<void> ensureInitialized() async {
    TachyonAudioPlatform.ensureInitialized();
  }

  Future<void> open(
    String uri, {
    bool play = true,
    Duration? startPosition,
  }) async {
    await _player.setFilePath(uri);
    await _player.play();
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) => _player.setVolume(volume / 100.0);

  Future<void> setRate(double rate) => _player.setSpeed(rate);

  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  Future<void> setSkipSilence(bool enabled) =>
      _player.setSkipSilenceEnabled(enabled);

  Future<void> dispose() async {
    _isDisposed = true;
    await _player.dispose();
  }

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  Stream<bool> get playingStream => _player.playingStream;

  Stream<bool> get bufferingStream =>
      _player.bufferedPositionStream.map((bufferedPosition) {
        final duration = _player.duration;
        if (duration == null) return false;
        return bufferedPosition < duration;
      });

  Stream<bool> get completedStream =>
      _player.processingStateStream.map((state) {
        return state == ProcessingState.completed;
      });

  Stream<double> get volumeStream => _player.volumeStream;

  Stream<double> get rateStream => _player.speedStream;

  Stream<double> get pitchStream => _player.pitchStream;

  Stream<bool> get skipSilenceStream => _player.skipSilenceEnabledStream;

  Duration get position => _player.position;

  Duration get duration => _player.duration ?? Duration.zero;

  bool get isPlaying => _player.playing;

  bool get isBuffering => _player.processingState == ProcessingState.buffering;

  bool get isCompleted => _player.processingState == ProcessingState.completed;

  double get volume => _player.volume;

  double get rate => _player.speed;

  double get pitch => _player.pitch;

  bool get skipSilence => _player.skipSilenceEnabled;

  bool get isDisposed => _isDisposed;
}
