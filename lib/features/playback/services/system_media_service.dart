import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

import 'linux_mpris_bridge.dart';
import 'tachyon_audio_handler.dart';
import 'windows_smtc_bridge.dart';

/// Central coordinator for system media transport controls and notification services
/// across Android (Foreground Service / Notification), iOS (MPNowPlayingInfoCenter),
/// Linux (native MPRIS2 over D-Bus), and Windows (SMTC).
class SystemMediaService with WidgetsBindingObserver {
  final TachyonAudioHandler _handler;
  LinuxMprisBridge? _linuxBridge;
  WindowsSmtcBridge? _windowsBridge;

  SystemMediaService._(this._handler) {
    WidgetsBinding.instance.addObserver(this);
  }

  TachyonAudioHandler get handler => _handler;

  /// Initializes the multiplatform system media services.
  static Future<SystemMediaService> initialize({
    required TachyonBackendClient backendClient,
    required PlaybackController playbackController,
  }) async {
    debugPrint('[SystemMediaService] Initializing system media service...');

    // 1. Initialize AudioService handler
    late final TachyonAudioHandler handler;
    await AudioService.init(
      builder: () {
        handler = TachyonAudioHandler(
          backend: backendClient,
          playbackController: playbackController,
        );
        return handler;
      },
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.chomusuke.tachyon.playback',
        androidNotificationChannelName: 'Tachyon Music Playback',
        androidNotificationIcon: 'drawable/ic_launcher',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
      ),
    );

    final service = SystemMediaService._(handler);

    // 2. Initialize Linux MPRIS bridge if on Linux
    if (!kIsWeb && Platform.isLinux) {
      debugPrint(
        '[SystemMediaService] Platform is Linux. Starting LinuxMprisBridge...',
      );
      final linuxBridge = LinuxMprisBridge(
        handler: handler,
        playbackController: playbackController,
      );
      await linuxBridge.initialize();
      service._linuxBridge = linuxBridge;
      debugPrint(
        '[SystemMediaService] LinuxMprisBridge initialized successfully.',
      );
    }

    // 3. Initialize Windows SMTC bridge if on Windows
    if (!kIsWeb && Platform.isWindows) {
      debugPrint(
        '[SystemMediaService] Platform is Windows. Starting WindowsSmtcBridge...',
      );
      final windowsBridge = WindowsSmtcBridge(handler);
      await windowsBridge.initialize();
      service._windowsBridge = windowsBridge;
      debugPrint(
        '[SystemMediaService] WindowsSmtcBridge initialized successfully.',
      );
    }

    debugPrint('[SystemMediaService] Initialization complete.');
    return service;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When Android enters background or headless state, free visual image memory.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      debugPrint(
        '[SystemMediaService] AppLifecycleState changed to $state. Clearing image cache...',
      );
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linuxBridge?.dispose();
    _windowsBridge?.dispose();
    _handler.dispose();
  }
}
