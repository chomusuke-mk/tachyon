import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

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

  AudioPlayerAdapter({
    PlayerConfiguration configuration = const PlayerConfiguration(
      title: 'Tachyon',
      pitch: true,
    ),
  }) : _player = Player(configuration: configuration);

  /// Ensures native media_kit platform bindings are initialized once.
  static Future<void> ensureInitialized() async {
    MediaKit.ensureInitialized();
  }

  /// Configures platform-specific libmpv properties for optimal low-latency,
  /// pop-free audio streaming.
  Future<void> configurePlatformAudioDrivers() async {
    final platform = _player.platform as dynamic;
    try {
      if (Platform.isAndroid) {
        await platform.setProperty('ao', 'audiotrack,opensles');
      } else if (Platform.isIOS) {
        await platform.setProperty('ao', 'audiounit');
      } else if (Platform.isMacOS) {
        await platform.setProperty('ao', 'coreaudio');
      }

      // 'audio-stream-silence' keeps the audio sink alive between tracks,
      // avoiding annoying hardware sink open/close clicks and pops.
      // Omitted on iOS due to audiounit limitations.
      if (!Platform.isIOS) {
        await platform.setProperty('audio-stream-silence', 'yes');
      }

      // Disable automatic subtitle lookup for audio files
      await platform.setProperty('sub-auto', 'no');
    } catch (e) {
      debugPrint('[MediaKitPlayerAdapter] Driver config warning: $e');
    }
  }

  Future<void> open(
    String uri, {
    bool play = true,
    Duration? startPosition,
  }) async {
    await _player.open(Media(uri, start: startPosition), play: play);
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> stop() => _player.stop();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  Future<void> setRate(double rate) => _player.setRate(rate);

  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  Future<void> setProperty(String name, String value) async {
    final platform = _player.platform as dynamic;
    await platform.setProperty(name, value);
  }

  Future<void> dispose() async {
    _isDisposed = true;
    await _player.dispose();
  }

  Stream<Duration> get positionStream => _player.stream.position;

  Stream<Duration> get durationStream => _player.stream.duration;

  Stream<bool> get playingStream => _player.stream.playing;

  Stream<bool> get bufferingStream => _player.stream.buffering;

  Stream<bool> get completedStream => _player.stream.completed;

  Stream<double> get volumeStream => _player.stream.volume;

  Stream<double> get rateStream => _player.stream.rate;

  Stream<double> get pitchStream => _player.stream.pitch;

  Stream<double?> get bitrateStream => _player.stream.audioBitrate;

  Duration get position => _player.state.position;

  Duration get duration => _player.state.duration;

  bool get isPlaying => _player.state.playing;

  bool get isBuffering => _player.state.buffering;

  bool get isCompleted => _player.state.completed;

  double get volume => _player.state.volume;

  double get rate => _player.state.rate;

  double get pitch => _player.state.pitch;

  bool get isDisposed => _isDisposed;
}
