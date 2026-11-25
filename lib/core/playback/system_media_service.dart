import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/playback/bridges/linux_mpris_bridge.dart';
import 'package:tachyon/core/playback/bridges/windows_smtc_bridge.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/playback/tachyon_audio_handler.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';

/// Central coordinator for platform system media transport controls and
/// playback notification bridges (Android MediaSession, iOS MPNowPlaying,
/// Linux MPRIS2, and Windows SMTC).
class SystemMediaService {
  final TachyonAudioHandler _handler;
  LinuxMprisBridge? _linuxBridge;
  WindowsSmtcBridge? _windowsBridge;

  SystemMediaService._(this._handler);

  /// Active `audio_service` handler bridged to [PlaybackController].
  TachyonAudioHandler get handler => _handler;

  /// Initializes platform media notification services and binds them to
  /// [playbackController] and optional [lifecycleController].
  static Future<SystemMediaService> initialize({
    required PlaybackController playbackController,
    AppLifecycleController? lifecycleController,
  }) async {
    debugPrint('[SystemMediaService] Initializing system media service...');

    late final TachyonAudioHandler handler;
    await AudioService.init(
      builder: () {
        handler = TachyonAudioHandler(
          playbackController: playbackController,
          onTaskRemovedWhilePlaying: lifecycleController == null
              ? null
              : () => lifecycleController.handleTaskRemoved(isPlaying: true),
        );
        return handler;
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.chomusuke.tachyon.playback',
        androidNotificationChannelName: 'Tachyon Music Playback',
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
      ),
    );

    final service = SystemMediaService._(handler);

    if (!kIsWeb && PersistentBinaryStorage.isLinux) {
      debugPrint(
        '[SystemMediaService] Platform is Linux. Starting LinuxMprisBridge...',
      );
      final linuxBridge = LinuxMprisBridge(
        handler: handler,
        playbackController: playbackController,
        onRaiseRequested: lifecycleController == null
            ? null
            : () => unawaited(lifecycleController.restoreFromBackground()),
      );
      await linuxBridge.initialize();
      service._linuxBridge = linuxBridge;
      debugPrint(
        '[SystemMediaService] LinuxMprisBridge initialized successfully.',
      );
    }

    if (!kIsWeb && PersistentBinaryStorage.isWindows) {
      debugPrint(
        '[SystemMediaService] Platform is Windows. Starting WindowsSmtcBridge...',
      );
      final windowsBridge = WindowsSmtcBridge(handler);
      final ok = await windowsBridge.initialize();
      if (ok) {
        service._windowsBridge = windowsBridge;
        debugPrint(
          '[SystemMediaService] WindowsSmtcBridge initialized successfully.',
        );
      } else {
        debugPrint(
          '[SystemMediaService] WindowsSmtcBridge failed to initialize.',
        );
      }
    }

    debugPrint('[SystemMediaService] Initialization complete.');
    return service;
  }

  /// Disposes native OS media bridges and detaches [handler].
  void dispose() {
    _linuxBridge?.dispose();
    _windowsBridge?.dispose();
    _handler.dispose();
  }
}
