import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/core/backend/backend.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

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
  final TachyonBackendClient? _backendClient;
  LinuxMprisBridge? _linuxBridge;
  WindowsSmtcBridge? _windowsBridge;
  AppLifecycleListener? _lifecycleListener;

  SystemMediaService._(this._handler, [this._backendClient]) {
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
        androidNotificationIcon: 'drawable/ic_notification',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
      ),
    );

    final service = SystemMediaService._(handler, backendClient);

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

  bool _isBackgroundTrimmed = false;

  /// Enters or exits Minimized Mode, coordinating UI cache eviction,
  /// ticker suspension, backend IPC throttling, and native memory trimming.
  void setMinimizedMode(bool minimized) {
    if (_isMinimizedNotifier.value == minimized &&
        (minimized ? _isBackgroundTrimmed : !_isBackgroundTrimmed)) {
      return;
    }
    _isMinimizedNotifier.value = minimized;
    _backendClient?.setMinimized(minimized);

    if (minimized) {
      MemoryOptimizer.stopPeriodicTrimmer();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      AlbumArtImage.clearExistenceCache();
      try {
        SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          0,
        );
      } catch (_) {}
      if (!_isBackgroundTrimmed) {
        _isBackgroundTrimmed = true;
        MemoryOptimizer.trim(aggressive: true);
        // Schedule a zero-allocation purge after Dart_NotifyLowMemory() completes
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (_isBackgroundTrimmed) {
            MemoryOptimizer.trim(aggressive: false);
          }
        });
      }
    } else {
      _isBackgroundTrimmed = false;
      try {
        SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          4 * 1024 * 1024,
        );
      } catch (_) {}
      MemoryOptimizer.trim(aggressive: false);
      MemoryOptimizer.startPeriodicTrimmer();
    }
  }

  /// Static helper to update Minimized Mode state directly (e.g. from lifecycle
  /// listeners or tests when a full [SystemMediaService] instance is not active).
  static void updateMinimizedState(
    bool minimized, {
    TachyonBackendClient? backendClient,
  }) {
    if (_isMinimizedNotifier.value == minimized) return;
    _isMinimizedNotifier.value = minimized;
    backendClient?.setMinimized(minimized);
    if (minimized) {
      MemoryOptimizer.stopPeriodicTrimmer();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      AlbumArtImage.clearExistenceCache();
      MemoryOptimizer.trim(aggressive: true);
    } else {
      MemoryOptimizer.trim(aggressive: false);
      MemoryOptimizer.startPeriodicTrimmer();
    }
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
