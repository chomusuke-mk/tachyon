import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/app_memory_coordinator.dart';
import 'package:tachyon/core/lifecycle/desktop_tray_service.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';

/// Coordinates the 3-state application lifecycle ([AppLifecycleMode.active],
/// [AppLifecycleMode.suspended], and [AppLifecycleMode.background]) across
/// desktop windows, mobile lifecycle events, playback UI throttling, memory
/// compaction, and the desktop system tray.
class AppLifecycleController extends ChangeNotifier
    with WidgetsBindingObserver {
  static const _log = ScopedLogger('AppLifecycle');

  final WindowControlBridge _windowBridge;
  final PlaybackController? _playbackController;
  final DesktopTrayService? _trayService;
  final bool _startTrimmerOnActive;
  final Future<void> Function()? _onCloseRequested;

  final ValueNotifier<AppLifecycleMode> _modeNotifier =
      ValueNotifier<AppLifecycleMode>(AppLifecycleMode.active);

  AppLifecycleListener? _lifecycleListener;
  bool _lastWindowMinimized = false;
  bool _isDisposed = false;

  /// Creates an [AppLifecycleController].
  ///
  /// Wires native window updates from [windowBridge], throttles UI updates on
  /// playback, controls tray visibility in background mode, and responds to OS
  /// lifecycle transitions. When [observeFlutterLifecycle] is `true`, attaches
  /// an [AppLifecycleListener] to [WidgetsBinding].
  AppLifecycleController({
    required this._windowBridge,
    this._playbackController,
    this._trayService,
    this._startTrimmerOnActive = true,
    bool observeFlutterLifecycle = true,
    this._onCloseRequested,
  }) {
    _lastWindowMinimized = _windowBridge.windowState.isMinimized;
    _windowBridge.onWindowStateChanged = _handleWindowStateChanged;
    _windowBridge.onBackgroundRequested = enterBackground;
    _windowBridge.onTrayAction = _handleTrayAction;
    _trayService?.attachLifecycleController(this);
    _log.d(
      'Initialized observeFlutterLifecycle=$observeFlutterLifecycle '
      'isDesktop=${_windowBridge.isDesktopPlatform} '
      'initialMinimized=$_lastWindowMinimized',
    );

    if (observeFlutterLifecycle) {
      _lifecycleListener = AppLifecycleListener(
        onHide: _handleFlutterHiddenOrPaused,
        onPause: _handleFlutterHiddenOrPaused,
        onShow: _handleFlutterShownOrResumed,
        onResume: _handleFlutterShownOrResumed,
        onDetach: _handleFlutterDetached,
      );
    }
  }

  /// Reactive listenable exposing the current [AppLifecycleMode].
  ValueListenable<AppLifecycleMode> get modeListenable => _modeNotifier;

  /// Current application execution and power mode.
  AppLifecycleMode get mode => _modeNotifier.value;

  /// Bridge used to inspect and control the native desktop window.
  WindowControlBridge get windowBridge => _windowBridge;

  /// Whether the application is currently in [AppLifecycleMode.active].
  bool get isActive => mode == AppLifecycleMode.active;

  /// Whether the application is currently in [AppLifecycleMode.suspended].
  bool get isSuspended => mode == AppLifecycleMode.suspended;

  /// Whether the application is currently in [AppLifecycleMode.background].
  bool get isBackground => mode == AppLifecycleMode.background;

  /// Whether UI rendering/updates should be suppressed (`!isActive`).
  bool get isUiThrottled => mode != AppLifecycleMode.active;

  /// Transitions the application to [AppLifecycleMode.active].
  Future<void> enterActive() async {
    if (_isDisposed) return;
    _log.d('enterActive requested (currentMode=${mode.name})');
    if (mode == AppLifecycleMode.background) {
      await restoreFromBackground();
      return;
    }
    _applyMode(AppLifecycleMode.active);
  }

  /// Transitions the application to [AppLifecycleMode.suspended].
  ///
  /// Has no effect while already in [AppLifecycleMode.background] so background
  /// tray / headless execution cannot be downgraded to suspended mode.
  void enterSuspended() {
    if (_isDisposed || mode == AppLifecycleMode.background) {
      _log.d(
        'enterSuspended ignored (disposed=$_isDisposed, currentMode=${mode.name})',
      );
      return;
    }
    _log.d('enterSuspended requested (currentMode=${mode.name})');
    _applyMode(AppLifecycleMode.suspended);
  }

  /// Transitions the application into [AppLifecycleMode.background].
  ///
  /// Dismisses active overlays, unmounts the entire Flutter UI tree, applies
  /// aggressive memory/cache purges, hides the desktop window, and activates the
  /// desktop system tray icon.
  Future<void> enterBackground() async {
    if (_isDisposed || mode == AppLifecycleMode.background) {
      _log.d(
        'enterBackground ignored (disposed=$_isDisposed, currentMode=${mode.name})',
      );
      return;
    }
    _log.d(
      'enterBackground requested (currentMode=${mode.name}, isDesktop=${_windowBridge.isDesktopPlatform})',
    );
    ToastUtils.dismissAll();
    _applyMode(AppLifecycleMode.background);
    if (_windowBridge.isDesktopPlatform) {
      await _trayService?.setVisible(true);
      await _windowBridge.enterBackgroundMode();
    }
  }

  /// Restores the application from [AppLifecycleMode.background] to
  /// [AppLifecycleMode.active], showing the window and remounting the shell UI.
  Future<void> restoreFromBackground() async {
    if (_isDisposed) return;
    _log.d(
      'restoreFromBackground requested (currentMode=${mode.name}, isDesktop=${_windowBridge.isDesktopPlatform})',
    );
    if (_windowBridge.isDesktopPlatform) {
      await _trayService?.setVisible(false);
      await _windowBridge.restoreFromBackground();
    }
    _applyMode(AppLifecycleMode.active);
  }

  /// Handles Android task removal (`onTaskRemoved`) when swiped from recents.
  ///
  /// Enters [AppLifecycleMode.background] when audio is actively playing so the
  /// foreground media notification stays alive while the UI is unmounted.
  Future<void> handleTaskRemoved({required bool isPlaying}) async {
    if (_isDisposed) return;
    _log.d('handleTaskRemoved(isPlaying=$isPlaying, currentMode=${mode.name})');
    if (isPlaying) {
      await enterBackground();
    } else {
      enterSuspended();
    }
  }

  /// Minimizes the desktop window and immediately enters [AppLifecycleMode.suspended].
  Future<void> minimizeWindow() async {
    _log.d('minimizeWindow requested');
    enterSuspended();
    await _windowBridge.minimizeWindow();
  }

  /// Toggles the desktop window between normal and maximized bounds.
  Future<void> toggleMaximizeWindow() {
    _log.d('toggleMaximizeWindow requested');
    return _windowBridge.toggleMaximizeWindow();
  }

  /// Closes the desktop window cleanly, hiding any active tray icon first.
  Future<void> closeApplication() async {
    if (_isDisposed) return;
    _log.i('closeApplication requested (currentMode=${mode.name})');
    await _trayService?.setVisible(false);
    await _playbackController?.flushStatePersistence();
    if (_onCloseRequested != null) {
      await _onCloseRequested();
    } else {
      await _windowBridge.closeWindow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    _log.d(
      'Flutter AppLifecycleState changed: $state (currentMode=${mode.name}, isPlaying=${_playbackController?.isPlaying})',
    );
    switch (state) {
      case AppLifecycleState.detached:
        _handleFlutterDetached();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _handleFlutterHiddenOrPaused();
        break;
      case AppLifecycleState.resumed:
        _handleFlutterShownOrResumed();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _handleFlutterDetached() {
    if (_isDisposed) return;
    final playing = _playbackController?.isPlaying ?? false;
    _log.d(
      '_handleFlutterDetached (currentMode=${mode.name}, isPlaying=$playing)',
    );
    if (playing) {
      unawaited(enterBackground());
    } else {
      enterSuspended();
    }
  }

  void _handleFlutterHiddenOrPaused() {
    if (_isDisposed || mode == AppLifecycleMode.background) {
      _log.d(
        '_handleFlutterHiddenOrPaused ignored (disposed=$_isDisposed, mode=${mode.name})',
      );
      return;
    }
    _log.d('_handleFlutterHiddenOrPaused -> enterSuspended()');
    enterSuspended();
  }

  void _handleFlutterShownOrResumed() {
    if (_isDisposed) return;
    _log.d(
      '_handleFlutterShownOrResumed (mode=${mode.name}, isDesktop=${_windowBridge.isDesktopPlatform})',
    );
    if (mode == AppLifecycleMode.background) {
      // On mobile (Android), resuming the Activity means the user tapped the
      // launcher or media notification to bring the app back on screen.
      if (!_windowBridge.isDesktopPlatform) {
        unawaited(restoreFromBackground());
      }
      return;
    }
    unawaited(enterActive());
  }

  void _handleWindowStateChanged(DesktopWindowState state) {
    if (_isDisposed) return;
    final wasMinimized = _lastWindowMinimized;
    _lastWindowMinimized = state.isMinimized;
    _log.d(
      'WindowState received: minimized=${state.isMinimized} focused=${state.isFocused} '
      'maximized=${state.isMaximized} hiddenToTray=${state.isHiddenToTray} '
      'wasMinimized=$wasMinimized (currentMode=${mode.name})',
    );
    if (mode == AppLifecycleMode.background || state.isHiddenToTray) {
      _log.d(
        'WindowState ignored because mode=${mode.name} hiddenToTray=${state.isHiddenToTray}',
      );
      return;
    }

    if (state.isMinimized) {
      _log.d('Window minimized -> entering suspended mode immediately');
      enterSuspended();
      return;
    }

    if (mode == AppLifecycleMode.suspended &&
        (state.isFocused || wasMinimized)) {
      _log.d(
        'Window restored (focused=${state.isFocused}, wasMinimized=$wasMinimized) -> entering active mode',
      );
      _applyMode(AppLifecycleMode.active);
      return;
    }

    _log.d(
      'Window state kept mode=${mode.name} '
      '(minimized=false, focused=${state.isFocused})',
    );
  }

  void _handleTrayAction(DesktopTrayAction action) {
    if (_isDisposed) return;
    _log.d('Tray action received: $action');
    switch (action) {
      case DesktopTrayAction.restore:
        unawaited(restoreFromBackground());
        break;
      case DesktopTrayAction.playPause:
        unawaited(_playbackController?.playOrPause());
        break;
      case DesktopTrayAction.next:
        unawaited(_playbackController?.next());
        break;
      case DesktopTrayAction.previous:
        unawaited(_playbackController?.previous());
        break;
      case DesktopTrayAction.toggleShuffle:
        unawaited(_playbackController?.toggleShuffle());
        break;
      case DesktopTrayAction.quit:
        unawaited(closeApplication());
        break;
    }
  }

  void _applyMode(AppLifecycleMode nextMode) {
    if (_isDisposed) return;
    if (_modeNotifier.value == nextMode) {
      _log.vLazy(() => '_applyMode unchanged: ${nextMode.name}');
      return;
    }
    final prev = _modeNotifier.value;
    _log.i('Mode transition: ${prev.name} -> ${nextMode.name}');
    _modeNotifier.value = nextMode;
    _playbackController?.setLifecycleMode(nextMode);
    AppMemoryCoordinator.applyPolicy(
      nextMode,
      startTrimmerInActive: _startTrimmerOnActive,
    );
    notifyListeners();
    if (prev == AppLifecycleMode.background &&
        nextMode == AppLifecycleMode.active) {
      SchedulerBinding.instance.scheduleForcedFrame();
    }
  }

  @override
  void dispose() {
    _log.d('Disposed');
    _isDisposed = true;
    AppMemoryCoordinator.cancelPendingTrims();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    super.dispose();
  }
}
