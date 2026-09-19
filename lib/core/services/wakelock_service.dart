import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Defensive cross-platform wrapper for [WakelockPlus].
///
/// Prevents unhandled exceptions in headless testing environments or
/// unsupported platforms.
abstract final class WakelockService {
  static bool _isEnabled = false;
  static bool get isEnabled => _isEnabled;

  /// Acquires display wakelock, keeping the screen awake during active playback.
  static Future<void> enable() async {
    if (kIsWeb) return;
    try {
      await WakelockPlus.enable();
      _isEnabled = true;
    } catch (e) {
      debugPrint('WakelockService.enable failed: $e');
    }
  }

  /// Releases display wakelock when playback is paused or Now Playing is dismissed.
  static Future<void> disable() async {
    if (kIsWeb) return;
    try {
      await WakelockPlus.disable();
      _isEnabled = false;
    } catch (e) {
      debugPrint('WakelockService.disable failed: $e');
    }
  }
}
