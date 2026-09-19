import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

// ============================================================================
// AUDIO PLAYER ADAPTER ABSTRACTION
// ============================================================================

/// Clean abstraction over underlying audio players (such as `media_kit.Player`),
/// enabling 100% deterministic testing in headless CI and unit test environments
/// where native libmpv or physical audio hardware are unavailable.
abstract class AudioPlayerAdapter {
  // --------------------------------------------------------------------------
  // Playback Controls
  // --------------------------------------------------------------------------
  Future<void> open(String uri, {bool play = true, Duration? startPosition});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setProperty(String name, String value);
  Future<void> dispose();

  // --------------------------------------------------------------------------
  // Observable Streams
  // --------------------------------------------------------------------------
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<double> get volumeStream;
  Stream<double> get rateStream;
  Stream<double> get pitchStream;
  Stream<double?> get bitrateStream;

  // --------------------------------------------------------------------------
  // Instantaneous State Accessors
  // --------------------------------------------------------------------------
  Duration get position;
  Duration get duration;
  bool get isPlaying;
  bool get isBuffering;
  bool get isCompleted;
  double get volume;
  double get rate;
  double get pitch;
  bool get isDisposed;
}

// ============================================================================
// PRODUCTION MEDIA_KIT PLAYER ADAPTER
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
class MediaKitPlayerAdapter implements AudioPlayerAdapter {
  final Player _player;
  bool _isDisposed = false;

  MediaKitPlayerAdapter({
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

  @override
  Future<void> open(
    String uri, {
    bool play = true,
    Duration? startPosition,
  }) async {
    await _player.open(Media(uri, start: startPosition), play: play);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setPitch(double pitch) => _player.setPitch(pitch);

  @override
  Future<void> setProperty(String name, String value) async {
    final platform = _player.platform as dynamic;
    await platform.setProperty(name, value);
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    await _player.dispose();
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<double> get volumeStream => _player.stream.volume;

  @override
  Stream<double> get rateStream => _player.stream.rate;

  @override
  Stream<double> get pitchStream => _player.stream.pitch;

  @override
  Stream<double?> get bitrateStream => _player.stream.audioBitrate;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  bool get isBuffering => _player.state.buffering;

  @override
  bool get isCompleted => _player.state.completed;

  @override
  double get volume => _player.state.volume;

  @override
  double get rate => _player.state.rate;

  @override
  double get pitch => _player.state.pitch;

  @override
  bool get isDisposed => _isDisposed;
}

// ============================================================================
// DETERMINISTIC MOCK AUDIO PLAYER ADAPTER (FOR CI & TESTS)
// ============================================================================

/// In-memory mock adapter satisfying [AudioPlayerAdapter] without requiring
/// native libmpv or physical audio hardware.
///
/// Provides programmable stream emissions, call logs, property tracking,
/// and step-by-step playback simulation.
class MockAudioPlayerAdapter implements AudioPlayerAdapter {
  final String id;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isCompleted = false;
  double _volume = 100.0;
  double _rate = 1.0;
  double _pitch = 1.0;
  double? _bitrate = 320.0;
  bool _isDisposed = false;

  final Map<String, String> properties = {};

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _bufferingController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _completedController =
      StreamController<bool>.broadcast();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final StreamController<double> _rateController =
      StreamController<double>.broadcast();
  final StreamController<double> _pitchController =
      StreamController<double>.broadcast();
  final StreamController<double?> _bitrateController =
      StreamController<double?>.broadcast();

  MockAudioPlayerAdapter({this.id = 'mock_player'});

  // --------------------------------------------------------------------------
  // Simulation Helpers for Tests
  // --------------------------------------------------------------------------

  void simulatePosition(Duration pos) {
    _position = pos;
    _positionController.add(_position);
  }

  void simulateDuration(Duration dur) {
    _duration = dur;
    _durationController.add(_duration);
  }

  void simulateBuffering(bool buffering) {
    _isBuffering = buffering;
    _bufferingController.add(_isBuffering);
  }

  void simulateCompleted() {
    _isCompleted = true;
    _isPlaying = false;
    _completedController.add(true);
    _playingController.add(false);
  }

  void simulateBitrate(double? bitrate) {
    _bitrate = bitrate;
    _bitrateController.add(_bitrate);
  }

  void simulatePlaying(bool playing) {
    _isPlaying = playing;
    _playingController.add(_isPlaying);
  }

  // --------------------------------------------------------------------------
  // AudioPlayerAdapter Methods
  // --------------------------------------------------------------------------

  @override
  Future<void> open(
    String uri, {
    bool play = true,
    Duration? startPosition,
  }) async {
    debugPrint('$id.open($uri, play: $play, start: $startPosition)');
    _isCompleted = false;
    _position = startPosition ?? Duration.zero;
    _isPlaying = play;
    _positionController.add(_position);
    _playingController.add(_isPlaying);
  }

  @override
  Future<void> play() async {
    debugPrint('$id.play()');
    _isPlaying = true;
    _isCompleted = false;
    _playingController.add(true);
  }

  @override
  Future<void> pause() async {
    debugPrint('$id.pause()');
    _isPlaying = false;
    _playingController.add(false);
  }

  @override
  Future<void> stop() async {
    debugPrint('$id.stop()');
    _isPlaying = false;
    _position = Duration.zero;
    _playingController.add(false);
    _positionController.add(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('$id.seek($position)');
    _position = position;
    _positionController.add(_position);
  }

  @override
  Future<void> setVolume(double volume) async {
    debugPrint('$id.setVolume($volume)');
    _volume = volume;
    _volumeController.add(volume);
  }

  @override
  Future<void> setRate(double rate) async {
    debugPrint('$id.setRate($rate)');
    _rate = rate;
    _rateController.add(rate);
  }

  @override
  Future<void> setPitch(double pitch) async {
    debugPrint('$id.setPitch($pitch)');
    _pitch = pitch;
    _pitchController.add(pitch);
  }

  @override
  Future<void> setProperty(String name, String value) async {
    debugPrint('$id.setProperty($name, $value)');
    properties[name] = value;
  }

  @override
  Future<void> dispose() async {
    debugPrint('$id.dispose()');
    _isDisposed = true;
    await _positionController.close();
    await _durationController.close();
    await _playingController.close();
    await _bufferingController.close();
    await _completedController.close();
    await _volumeController.close();
    await _rateController.close();
    await _pitchController.close();
    await _bitrateController.close();
  }

  @override
  Stream<Duration> get positionStream => _positionController.stream;
  @override
  Stream<Duration> get durationStream => _durationController.stream;
  @override
  Stream<bool> get playingStream => _playingController.stream;
  @override
  Stream<bool> get bufferingStream => _bufferingController.stream;
  @override
  Stream<bool> get completedStream => _completedController.stream;
  @override
  Stream<double> get volumeStream => _volumeController.stream;
  @override
  Stream<double> get rateStream => _rateController.stream;
  @override
  Stream<double> get pitchStream => _pitchController.stream;
  @override
  Stream<double?> get bitrateStream => _bitrateController.stream;

  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  bool get isPlaying => _isPlaying;
  @override
  bool get isBuffering => _isBuffering;
  @override
  bool get isCompleted => _isCompleted;
  @override
  double get volume => _volume;
  @override
  double get rate => _rate;
  @override
  double get pitch => _pitch;
  @override
  bool get isDisposed => _isDisposed;
}
