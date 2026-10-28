import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/shared/utils/app_memory_coordinator.dart';

import 'linux_mpris_bridge.dart';
import 'tachyon_audio_handler.dart';
import 'windows_smtc_bridge.dart';

/// Central coordinator for system media transport controls, notification services,
/// and Minimized Mode across Android, iOS, Linux (GTK headerbar & window state),
/// macOS, and Windows.
class SystemMediaService with WidgetsBindingObserver {
  static const MethodChannel windowStateChannel = MethodChannel(
    'dev.chomusuke.tachyon/window_state',
  );

  static final ValueNotifier<bool> _isMinimizedNotifier = ValueNotifier<bool>(
    false,
  );

  /// Reactive listenable indicating whether the application is currently in
  /// Minimized Mode (backgrounded on mobile, minimized on desktop, or minimized
  /// via the Linux window headerbar minimize button).
  static ValueListenable<bool> get isMinimizedListenable =>
      _isMinimizedNotifier;

  /// Whether the application is currently in Minimized Mode.
  static bool get isMinimized => _isMinimizedNotifier.value;

  final TachyonAudioHandler _handler;
  final PlaybackController? _playbackController;
  LinuxMprisBridge? _linuxBridge;
  WindowsSmtcBridge? _windowsBridge;
  AppLifecycleListener? _lifecycleListener;

  SystemMediaService._(this._handler, [this._playbackController]) {
    WidgetsBinding.instance.addObserver(this);
    _lifecycleListener = AppLifecycleListener(
      onHide: () => setMinimizedMode(true),
      onPause: () => setMinimizedMode(true),
      onShow: () => setMinimizedMode(false),
      onResume: () => setMinimizedMode(false),
    );
    _setupLinuxWindowStateChannel();
  }

  TachyonAudioHandler get handler => _handler;

  void _setupLinuxWindowStateChannel() {
    windowStateChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMinimizedChanged') {
        final minimized = call.arguments == true;
        setMinimizedMode(minimized);
      }
      return null;
    });
  }

  /// Initializes the multiplatform system media services.
  static Future<SystemMediaService> initialize({
    required PlaybackController playbackController,
  }) async {
    debugPrint('[SystemMediaService] Initializing system media service...');

    // 1. Initialize AudioService handler
    late final TachyonAudioHandler handler;
    await AudioService.init(
      builder: () {
        handler = TachyonAudioHandler(
          playbackController: playbackController,
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

    final service = SystemMediaService._(handler, playbackController);

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

  /// Enters or exits Minimized Mode, coordinating UI cache eviction,
  /// ticker suspension, position throttling, and native memory trimming.
  void setMinimizedMode(bool minimized) {
    if (_isMinimizedNotifier.value == minimized) {
      return;
    }
    _isMinimizedNotifier.value = minimized;
    _playbackController?.setMinimized(minimized);
    AppMemoryCoordinator.applyMinimizedMemoryPolicy(minimized);
  }

  /// Static helper to update Minimized Mode state directly (e.g. from lifecycle
  /// listeners or tests when a full [SystemMediaService] instance is not active).
  static void updateMinimizedState(
    bool minimized, {
    PlaybackController? playbackController,
  }) {
    if (_isMinimizedNotifier.value == minimized) return;
    _isMinimizedNotifier.value = minimized;
    playbackController?.setMinimized(minimized);
    AppMemoryCoordinator.applyMinimizedMemoryPolicy(minimized);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      setMinimizedMode(true);
      return;
    }

    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      setMinimizedMode(true);
    } else if (state == AppLifecycleState.resumed) {
      setMinimizedMode(false);
    }
  }

  void dispose() {
    windowStateChannel.setMethodCallHandler(null);
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    WidgetsBinding.instance.removeObserver(this);
    _linuxBridge?.dispose();
    _windowsBridge?.dispose();
    _handler.dispose();
  }
}
