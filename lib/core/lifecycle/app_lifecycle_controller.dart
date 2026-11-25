import 'dart:async';

import 'package:flutter/foundation.dart';
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
    _log.d(
      'Initialized observeFlutterLifecycle=$observeFlutterLifecycle '
      'focusLossDebounce=${_focusLossDebounce.inMilliseconds}ms '
      'isDesktop=${_windowBridge.isDesktopPlatform}',
    );

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
    _log.d('enterActive requested (currentMode=${mode.name})');
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
    if (_isDisposed || mode == AppLifecycleMode.background) {
      _log.d(
        'enterSuspended ignored (disposed=$_isDisposed, currentMode=${mode.name})',
      );
      return;
    }
    _log.d('enterSuspended requested (currentMode=${mode.name})');
    _cancelFocusDebounce();
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
    _log.d(
      'restoreFromBackground requested (currentMode=${mode.name}, isDesktop=${_windowBridge.isDesktopPlatform})',
    );
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
    _log.d(
      'Flutter AppLifecycleState changed: $state (currentMode=${mode.name}, isPlaying=${_playbackController?.isPlaying})',
    );
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
    _log.d(
      'WindowState received: minimized=${state.isMinimized} focused=${state.isFocused} '
      'maximized=${state.isMaximized} hiddenToTray=${state.isHiddenToTray} '
      '(currentMode=${mode.name})',
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

    if (!state.isFocused) {
      if (_focusLossDebounce == Duration.zero) {
        _log.d('Window unfocused (debounce=0ms) -> entering suspended mode immediately');
        enterSuspended();
      } else {
        _log.d(
          'Window unfocused -> scheduling ${_focusLossDebounce.inMilliseconds}ms debounce timer',
        );
        _focusDebounceTimer?.cancel();
        _focusDebounceTimer = Timer(_focusLossDebounce, () {
          if (_isDisposed || mode == AppLifecycleMode.background) {
            _log.d(
              'Focus-loss debounce fired but ignored (disposed=$_isDisposed, mode=${mode.name})',
            );
            return;
          }
          final latest = _windowBridge.windowState;
          _log.d(
            'Focus-loss debounce fired: latest.isFocused=${latest.isFocused} '
            'latest.isMinimized=${latest.isMinimized} latest.isHiddenToTray=${latest.isHiddenToTray}',
          );
          if (!latest.isFocused && !latest.isHiddenToTray) {
            enterSuspended();
          }
        });
      }
      return;
    }

    _log.d('Window focused -> cancelling focus debounce and entering active mode');
    _cancelFocusDebounce();
    _applyMode(AppLifecycleMode.active);
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
  }

  void _cancelFocusDebounce() {
    if (_focusDebounceTimer != null && _focusDebounceTimer!.isActive) {
      _log.d('Cancelled pending focus-loss debounce timer');
    }
    _focusDebounceTimer?.cancel();
    _focusDebounceTimer = null;
  }

  @override
  void dispose() {
    _log.d('Disposed');
    _isDisposed = true;
    _cancelFocusDebounce();
    AppMemoryCoordinator.cancelPendingTrims();
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
