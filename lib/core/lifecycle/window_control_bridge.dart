import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';

/// Platform channel action identifier emitted by native desktop trays.
enum DesktopTrayAction {
  /// Restores the main window from the system tray.
  restore,

  /// Toggles playback between playing and paused.
  playPause,

  /// Skips to the next track in the playback queue.
  next,

  /// Skips to the previous track in the playback queue.
  previous,

  /// Toggles playback shuffle mode.
  toggleShuffle,

  /// Exits the application cleanly.
  quit,
}

/// Callback invoked when native window state updates arrive from the runner.
typedef NativeWindowStateCallback = void Function(DesktopWindowState state);

/// Callback invoked when a native desktop tray action is triggered.
typedef NativeTrayActionCallback = void Function(DesktopTrayAction action);

/// Bidirectional bridge over `'dev.chomusuke.tachyon/window_state'` connecting
/// Dart lifecycle logic with native desktop runners (Linux GTK, Windows Win32,
/// macOS AppKit).
class WindowControlBridge {
  /// Method channel shared with native desktop platform runners.
  static const MethodChannel channel = MethodChannel(
    'dev.chomusuke.tachyon/window_state',
  );

  final Future<T?> Function<T>(String method, [Object? arguments])?
  _invokeOverride;
  final bool? _usesFlutterTitleBarOverride;
  final bool? _isDesktopOverride;
  final bool _attachChannelHandler;

  final ValueNotifier<DesktopWindowState> _windowStateNotifier =
      ValueNotifier<DesktopWindowState>(const DesktopWindowState());

  bool _hasNativeChannel = false;
  bool _isDisposed = false;

  /// Invoked whenever the native runner emits a window state update.
  NativeWindowStateCallback? onWindowStateChanged;

  /// Invoked whenever the native runner tray emits a menu or click action.
  NativeTrayActionCallback? onTrayAction;

  /// Invoked when a native headerbar "Send to background" button is clicked.
  VoidCallback? onBackgroundRequested;

  /// Creates a [WindowControlBridge].
  ///
  /// Optional overrides allow deterministic unit and widget testing without
  /// requiring a live native runner channel.
  WindowControlBridge({
    this._invokeOverride,
    this._usesFlutterTitleBarOverride,
    this._isDesktopOverride,
    this._attachChannelHandler = true,
  });

  /// Reactive listenable of the latest native [DesktopWindowState].
  ValueListenable<DesktopWindowState> get windowStateListenable =>
      _windowStateNotifier;

  /// Latest native [DesktopWindowState] snapshot.
  DesktopWindowState get windowState => _windowStateNotifier.value;

  /// Whether a native desktop runner channel responded to initialization.
  bool get hasNativeChannel => _hasNativeChannel;

  /// Whether the host platform is a desktop operating system.
  bool get isDesktopPlatform {
    if (_isDesktopOverride != null) return _isDesktopOverride;
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  /// Whether Flutter should render [DesktopWindowBar] inside the app viewport.
  ///
  /// Returns `true` only when a native runner channel is active and the host
  /// does not already provide a native custom headerbar (for example Windows,
  /// macOS, or an undecorated Linux window). Defaults to `false` in unit tests
  /// unless explicitly overridden.
  bool get usesFlutterTitleBar {
    if (_usesFlutterTitleBarOverride != null) {
      return _usesFlutterTitleBarOverride;
    }
    if (!isDesktopPlatform || !_hasNativeChannel) return false;
    final state = _windowStateNotifier.value;
    return !state.hasNativeHeaderBar && !state.hasSystemDecorations;
  }

  /// Initializes the platform channel handler and queries initial window state.
  Future<void> initialize() async {
    if (_isDisposed) return;

    if (_attachChannelHandler && _invokeOverride == null) {
      channel.setMethodCallHandler(_handleIncomingCall);
    }

    if (!isDesktopPlatform && _invokeOverride == null) {
      return;
    }

    try {
      final raw = await _invoke<Map<Object?, Object?>>('getWindowState');
      if (raw != null && !_isDisposed) {
        _hasNativeChannel = true;
        _updateWindowState(
          DesktopWindowState.fromMap(raw, fallback: _windowStateNotifier.value),
        );
      }
    } on MissingPluginException {
      _hasNativeChannel = false;
    } catch (_) {
      _hasNativeChannel = false;
    }
  }

  Future<dynamic> _handleIncomingCall(MethodCall call) async {
    if (_isDisposed) return null;
    switch (call.method) {
      case 'onWindowStateChanged':
        _hasNativeChannel = true;
        if (call.arguments is Map) {
          final next = DesktopWindowState.fromMap(
            call.arguments as Map<Object?, Object?>,
            fallback: _windowStateNotifier.value,
          );
          _updateWindowState(next);
          onWindowStateChanged?.call(next);
        }
        break;
      case 'onMinimizedChanged':
        _hasNativeChannel = true;
        final minimized = call.arguments == true;
        final next = _windowStateNotifier.value.copyWith(isMinimized: minimized);
        _updateWindowState(next);
        onWindowStateChanged?.call(next);
        break;
      case 'onBackgroundRequested':
        onBackgroundRequested?.call();
        break;
      case 'onTrayAction':
        final actionName = call.arguments as String?;
        final action = _parseTrayAction(actionName);
        if (action != null) {
          onTrayAction?.call(action);
        }
        break;
    }
    return null;
  }

  void _updateWindowState(DesktopWindowState next) {
    if (_isDisposed || _windowStateNotifier.value == next) return;
    _windowStateNotifier.value = next;
  }

  static DesktopTrayAction? _parseTrayAction(String? action) {
    return switch (action) {
      'restore' => DesktopTrayAction.restore,
      'playPause' => DesktopTrayAction.playPause,
      'next' => DesktopTrayAction.next,
      'previous' => DesktopTrayAction.previous,
      'toggleShuffle' => DesktopTrayAction.toggleShuffle,
      'quit' => DesktopTrayAction.quit,
      _ => null,
    };
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (_invokeOverride != null) {
      return _invokeOverride<T>(method, arguments);
    }
    if (kIsWeb) return null;
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Minimizes the desktop application window to the taskbar.
  Future<void> minimizeWindow() => _invoke<void>('minimize');

  /// Toggles between maximized and normal restored window bounds.
  Future<void> toggleMaximizeWindow() => _invoke<void>('toggleMaximize');

  /// Closes the desktop application window.
  Future<void> closeWindow() => _invoke<void>('closeWindow');

  /// Starts an interactive OS window drag from the custom Flutter titlebar.
  Future<void> startWindowDrag() => _invoke<void>('startWindowDrag');

  /// Hides the desktop window when entering [AppLifecycleMode.background].
  Future<void> enterBackgroundMode() async {
    _updateWindowState(_windowStateNotifier.value.copyWith(isHiddenToTray: true));
    await _invoke<void>('enterBackgroundMode');
  }

  /// Shows and focuses the desktop window when exiting [AppLifecycleMode.background].
  Future<void> restoreFromBackground() async {
    _updateWindowState(
      _windowStateNotifier.value.copyWith(
        isHiddenToTray: false,
        isMinimized: false,
      ),
    );
    await _invoke<void>('restoreFromBackground');
  }

  /// Updates the native system tray icon visibility, tooltip, and menu labels
  /// on platforms whose tray lives in the native runner (Windows and macOS).
  Future<void> updateNativeTrayState({
    required bool visible,
    required String tooltip,
    required bool isPlaying,
    required bool isShuffled,
    required bool hasTrack,
    required String playLabel,
    required String pauseLabel,
    required String nextLabel,
    required String previousLabel,
    required String shuffleLabel,
    required String showAppLabel,
    required String quitLabel,
  }) {
    return _invoke<void>('updateTrayState', <String, Object?>{
      'visible': visible,
      'tooltip': tooltip,
      'isPlaying': isPlaying,
      'isShuffled': isShuffled,
      'hasTrack': hasTrack,
      'playLabel': playLabel,
      'pauseLabel': pauseLabel,
      'nextLabel': nextLabel,
      'previousLabel': previousLabel,
      'shuffleLabel': shuffleLabel,
      'showAppLabel': showAppLabel,
      'quitLabel': quitLabel,
    });
  }

  /// Sets the localized tooltip on native headerbar background buttons (Linux GTK).
  Future<void> setBackgroundButtonTooltip(String tooltip) {
    return _invoke<void>('setBackgroundButtonTooltip', tooltip);
  }

  /// Injects a synthetic [DesktopWindowState] update (for unit tests).
  @visibleForTesting
  void simulateWindowStateForTest(DesktopWindowState state) {
    _updateWindowState(state);
    onWindowStateChanged?.call(state);
  }

  /// Dispatches a synthetic [DesktopTrayAction] (for unit tests).
  @visibleForTesting
  void simulateTrayActionForTest(DesktopTrayAction action) {
    onTrayAction?.call(action);
  }

  /// Releases platform channel callbacks and internal notifiers.
  void dispose() {
    _isDisposed = true;
    if (_attachChannelHandler && _invokeOverride == null) {
      channel.setMethodCallHandler(null);
    }
    _windowStateNotifier.dispose();
  }
}
