import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';

/// Web no-op stub for the Linux MPRIS2 D-Bus bridge.
class LinuxMprisBridge {
  /// The audio handler associated with the bridge.
  final TachyonAudioHandler handler;

  /// The playback controller associated with the bridge.
  final PlaybackController playbackController;

  /// Debounce window for track metadata transitions.
  final Duration metadataDebounceDuration;

  /// Coalesce window for transport state changes.
  final Duration stateCoalesceDuration;

  /// Optional callback invoked when an MPRIS `Raise` request occurs.
  final VoidCallback? onRaiseRequested;

  /// Creates a no-op MPRIS bridge stub for [handler] and [playbackController].
  ///
  /// Accepts [metadataDebounceDuration], [stateCoalesceDuration], and
  /// [onRaiseRequested] to match the native constructor signature.
  LinuxMprisBridge({
    required this.handler,
    required this.playbackController,
    this.metadataDebounceDuration = const Duration(milliseconds: 60),
    this.stateCoalesceDuration = const Duration(milliseconds: 12),
    this.onRaiseRequested,
  });

  /// The number of emitted signals (always `0` on web).
  int get emittedSignalCount => 0;

  /// The registered D-Bus bus name (always `null` on web).
  String? get registeredBusName => null;

  /// The MPRIS playback status string (always `'Stopped'` on web).
  String get playbackStatus => 'Stopped';

  /// The MPRIS loop status string (always `'None'` on web).
  String get loopStatus => 'None';

  /// The playback rate (always `1.0` on web).
  double get rate => 1.0;

  /// Whether shuffle is enabled (always `false` on web).
  bool get shuffle => false;

  /// The normalized volume (always `1.0` on web).
  double get volume => 1.0;

  /// No-op initialization stub on web.
  Future<void> initialize() async {}

  /// No-op disposal stub on web.
  Future<void> dispose() async {}
}
