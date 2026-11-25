import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/app_memory_coordinator.dart';
import 'package:tachyon/core/lifecycle/desktop_tray_service.dart';
import 'package:tachyon/core/lifecycle/window_control_bridge.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/shared/utils/toast_utils.dart';

/// Coordinates the 3-state application lifecycle ([AppLifecycleMode.active],
/// [AppLifecycleMode.suspended], and [AppLifecycleMode.background]) across
/// desktop windows, mobile lifecycle events, playback UI throttling, memory
/// compaction, and the desktop system tray.
class AppLifecycleController extends ChangeNotifier
    with WidgetsBindingObserver {
  final WindowControlBridge _windowBridge;
  final PlaybackController? _playbackController;
  final DesktopTrayService? _trayService;
  final Duration _focusLossDebounce;
  final bool _startTrimmerOnActive;
  final Future<void> Function()? _onCloseRequested;

  final ValueNotifier<AppLifecycleMode> _modeNotifier =
      ValueNotifier<AppLifecycleMode>(AppLifecycleMode.active);

  AppLifecycleListener? _lifecycleListener;
  Timer? _focusDebounceTimer;
  bool _isDisposed = false;

  /// Creates an [AppLifecycleController].
  ///
  /// Wires native window updates from [windowBridge], throttles UI updates on
  /// playback, controls tray visibility in background mode, and debounces
  /// transient desktop focus-loss events. When [observeFlutterLifecycle] is
  /// `true`, attaches to [WidgetsBinding] and [AppLifecycleListener].
  AppLifecycleController({
    required this._windowBridge,
    this._playbackController,
    this._trayService,
    this._focusLossDebounce = const Duration(milliseconds: 150),
    this._startTrimmerOnActive = true,
    bool observeFlutterLifecycle = true,
    this._onCloseRequested,
  }) {
    _windowBridge.onWindowStateChanged = _handleWindowStateChanged;
    _windowBridge.onBackgroundRequested = enterBackground;
    _windowBridge.onTrayAction = _handleTrayAction;
    _trayService?.attachLifecycleController(this);

    if (observeFlutterLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleListener = AppLifecycleListener(
        onHide: _handleFlutterHiddenOrPaused,
        onPause: _handleFlutterHiddenOrPaused,
        onShow: _handleFlutterShownOrResumed,
        onResume: _handleFlutterShownOrResumed,
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
    _cancelFocusDebounce();
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
    if (_isDisposed || mode == AppLifecycleMode.background) return;
    _cancelFocusDebounce();
    _applyMode(AppLifecycleMode.suspended);
  }

  /// Transitions the application into [AppLifecycleMode.background].
  ///
  /// Dismisses active overlays, unmounts the entire Flutter UI tree, applies
  /// aggressive memory/cache purges, hides the desktop window, and activates the
  /// desktop system tray icon.
  Future<void> enterBackground() async {
    if (_isDisposed || mode == AppLifecycleMode.background) return;
    _cancelFocusDebounce();
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
    _cancelFocusDebounce();
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
    if (isPlaying) {
      await enterBackground();
    } else {
      enterSuspended();
    }
  }

  /// Minimizes the desktop window and immediately enters [AppLifecycleMode.suspended].
  Future<void> minimizeWindow() async {
    enterSuspended();
    await _windowBridge.minimizeWindow();
  }

  /// Toggles the desktop window between normal and maximized bounds.
  Future<void> toggleMaximizeWindow() => _windowBridge.toggleMaximizeWindow();

  /// Closes the desktop window cleanly, hiding any active tray icon first.
  Future<void> closeApplication() async {
    if (_isDisposed) return;
    _cancelFocusDebounce();
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
    switch (state) {
      case AppLifecycleState.detached:
        if (_playbackController?.isPlaying ?? false) {
          unawaited(enterBackground());
        } else {
          enterSuspended();
        }
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

  void _handleFlutterHiddenOrPaused() {
    if (_isDisposed || mode == AppLifecycleMode.background) return;
    enterSuspended();
  }

  void _handleFlutterShownOrResumed() {
    if (_isDisposed) return;
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
    if (mode == AppLifecycleMode.background || state.isHiddenToTray) {
      return;
    }

    if (state.isMinimized) {
      enterSuspended();
      return;
    }

    if (!state.isFocused) {
      if (_focusLossDebounce == Duration.zero) {
        enterSuspended();
      } else {
        _focusDebounceTimer?.cancel();
        _focusDebounceTimer = Timer(_focusLossDebounce, () {
          if (_isDisposed || mode == AppLifecycleMode.background) return;
          final latest = _windowBridge.windowState;
          if (!latest.isFocused && !latest.isHiddenToTray) {
            enterSuspended();
          }
        });
      }
      return;
    }

    _cancelFocusDebounce();
    _applyMode(AppLifecycleMode.active);
  }

  void _handleTrayAction(DesktopTrayAction action) {
    if (_isDisposed) return;
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
    if (_isDisposed || _modeNotifier.value == nextMode) return;
    _modeNotifier.value = nextMode;
    _playbackController?.setLifecycleMode(nextMode);
    AppMemoryCoordinator.applyPolicy(
      nextMode,
      startTrimmerInActive: _startTrimmerOnActive,
    );
    notifyListeners();
  }

  void _cancelFocusDebounce() {
    _focusDebounceTimer?.cancel();
    _focusDebounceTimer = null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelFocusDebounce();
    AppMemoryCoordinator.cancelPendingTrims();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
