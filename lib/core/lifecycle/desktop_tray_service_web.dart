import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';

/// Web stub implementation of [DesktopTrayService].
class DesktopTrayService {
  /// Creates a no-op tray service on Web platforms.
  DesktopTrayService({
    required PlaybackController playbackController,
    required LocaleController localeController,
    required WindowControlBridge windowBridge,
  });

  /// Attaches lifecycle callbacks (no-op on Web).
  void attachLifecycleController(AppLifecycleController lifecycleController) {}

  /// Initializes the tray backend (no-op on Web).
  Future<void> initialize() async {}

  /// Shows or hides the tray icon (no-op on Web).
  Future<void> setVisible(bool visible) async {}

  /// Releases tray resources (no-op on Web).
  Future<void> dispose() async {}
}
