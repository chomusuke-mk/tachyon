import 'package:tachyon/core/playback/tachyon_audio_handler.dart';

/// Web no-op stub for the Windows System Media Transport Controls bridge.
class WindowsSmtcBridge {
  /// The audio handler passed to the bridge.
  final TachyonAudioHandler handler;

  /// Creates a no-op Windows SMTC bridge stub for [handler].
  WindowsSmtcBridge(this.handler);

  /// Whether the Windows SMTC session is initialized (always `false` on web).
  bool get isInitialized => false;

  /// The loopback cover server port (always `null` on web).
  int? get coverServerPort => null;

  /// Returns `false` because Windows SMTC is unsupported on web.
  ///
  /// Ignores [externalLibrary].
  Future<bool> initialize({Object? externalLibrary}) async => false;

  /// No-op disposal stub on web.
  Future<void> dispose() async {}
}
