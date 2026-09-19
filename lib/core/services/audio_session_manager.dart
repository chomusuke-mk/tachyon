import 'dart:async';

import 'package:tachyon/core/services/audio_engine_service.dart';

// ============================================================================
// AUDIO SESSION & AUDIO FOCUS MANAGEMENT
// ============================================================================

/// Event payload for audio session focus changes.
enum AudioInterruptionType { pause, duck, unknown }

class AudioInterruptionEvent {
  final bool begin;
  final AudioInterruptionType type;

  const AudioInterruptionEvent({
    required this.begin,
    this.type = AudioInterruptionType.pause,
  });
}

/// Manages operating system audio session focus and peripheral disconnect events.
///
/// Features:
/// - Auto-pause on incoming phone calls, alarms, or audio interruptions.
/// - Auto-resume when transient interruption ends (only if playing prior to interruption).
/// - "Becoming Noisy" protection: auto-pause when headphones are unplugged or Bluetooth disconnects.
/// - Audio session activation when starting playback and deactivation when stopped.
class AudioSessionManager {
  final AudioEngineService audioEngineService;
  bool _wasPlayingBeforeInterruption = false;
  bool _isSessionActive = false;
  StreamSubscription<dynamic>? _interruptionSub;
  StreamSubscription<dynamic>? _becomingNoisySub;

  AudioSessionManager({required this.audioEngineService});

  bool get wasPlayingBeforeInterruption => _wasPlayingBeforeInterruption;
  bool get isSessionActive => _isSessionActive;

  /// Initializes audio session listeners.
  ///
  /// Connects to real or mock streams for audio interruptions and becoming noisy events.
  Future<void> init({
    Stream<AudioInterruptionEvent>? mockInterruptionStream,
    Stream<void>? mockBecomingNoisyStream,
  }) async {
    // 1. Listen for audio interruptions (calls, navigation alerts)
    if (mockInterruptionStream != null) {
      _interruptionSub = mockInterruptionStream.listen(handleInterruption);
    }

    // 2. Listen for becoming noisy (unplugged headphones / disconnected BT)
    if (mockBecomingNoisyStream != null) {
      _becomingNoisySub = mockBecomingNoisyStream.listen(
        (_) => handleBecomingNoisy(),
      );
    }
  }

  /// Handles audio interruptions from phone calls, alarms, or assistants.
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      if (audioEngineService.isPlaying) {
        _wasPlayingBeforeInterruption = true;
        audioEngineService.pause();
      }
    } else {
      if (_wasPlayingBeforeInterruption) {
        if (event.type == AudioInterruptionType.pause) {
          audioEngineService.play();
        }
        _wasPlayingBeforeInterruption = false;
      }
    }
  }

  /// Handles headphone unplugging or Bluetooth disconnection.
  ///
  /// Standard Android/iOS behavior mandates immediate pause to avoid public blasting.
  void handleBecomingNoisy() {
    if (audioEngineService.isPlaying) {
      audioEngineService.pause();
    }
  }

  /// Activates the operating system audio session when starting playback.
  Future<void> activateSession() async {
    if (_isSessionActive) return;
    _isSessionActive = true;
  }

  /// Deactivates the audio session when playback is paused or stopped.
  Future<void> deactivateSession() async {
    if (!_isSessionActive) return;
    _isSessionActive = false;
  }

  /// Cleans up listeners.
  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await deactivateSession();
  }
}
