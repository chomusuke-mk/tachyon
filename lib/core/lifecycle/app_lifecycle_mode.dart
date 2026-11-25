import 'package:flutter/foundation.dart';

/// Power and UI execution mode for the application lifecycle.
enum AppLifecycleMode {
  /// Foreground mode with full UI rendering, animations, and caches enabled.
  active,

  /// Suspended mode entered when minimized, unfocused on desktop, or switched
  /// away from on mobile.
  ///
  /// The widget tree stays mounted so navigation routes and scroll offsets are
  /// preserved, while UI updates and animations pause, image caches are
  /// cleared, and a moderate RAM trim runs.
  suspended,

  /// Background mode entered when sent to the desktop system tray or detached
  /// on Android while audio is playing.
  ///
  /// The entire UI tree is unmounted, maximum RAM and graphics cache purges
  /// run, and background playback plus system media/tray controls remain active.
  background,
}

/// Native memory reclamation intensity applied by [MemoryOptimizer].
enum MemoryTrimLevel {
  /// Minimal heap compaction suitable for routine idle intervals.
  light,

  /// Heap compaction and working-set trimming without unmapping code pages.
  moderate,

  /// Maximum heap, working-set, and POSIX page reclamation for background mode.
  aggressive,
}

/// Snapshot of native desktop window capabilities and state.
@immutable
class DesktopWindowState {
  /// Whether the host platform renders a native header bar (such as GNOME GTK).
  final bool hasNativeHeaderBar;

  /// Whether the host window renders OS window decorations around the client area.
  final bool hasSystemDecorations;

  /// Whether the window is currently minimized/iconified in the taskbar.
  final bool isMinimized;

  /// Whether the window currently holds keyboard/window focus.
  final bool isFocused;

  /// Whether the window is currently maximized.
  final bool isMaximized;

  /// Whether the window is currently hidden into the desktop system tray.
  final bool isHiddenToTray;

  /// Creates an immutable [DesktopWindowState].
  const DesktopWindowState({
    this.hasNativeHeaderBar = true,
    this.hasSystemDecorations = true,
    this.isMinimized = false,
    this.isFocused = true,
    this.isMaximized = false,
    this.isHiddenToTray = false,
  });

  /// Returns a copy of this state with the provided fields updated.
  DesktopWindowState copyWith({
    bool? hasNativeHeaderBar,
    bool? hasSystemDecorations,
    bool? isMinimized,
    bool? isFocused,
    bool? isMaximized,
    bool? isHiddenToTray,
  }) {
    return DesktopWindowState(
      hasNativeHeaderBar: hasNativeHeaderBar ?? this.hasNativeHeaderBar,
      hasSystemDecorations: hasSystemDecorations ?? this.hasSystemDecorations,
      isMinimized: isMinimized ?? this.isMinimized,
      isFocused: isFocused ?? this.isFocused,
      isMaximized: isMaximized ?? this.isMaximized,
      isHiddenToTray: isHiddenToTray ?? this.isHiddenToTray,
    );
  }

  /// Parses a native platform channel map into a [DesktopWindowState].
  factory DesktopWindowState.fromMap(
    Map<Object?, Object?> map, {
    DesktopWindowState fallback = const DesktopWindowState(),
  }) {
    bool readBool(String key, bool defaultValue) {
      final raw = map[key];
      return raw is bool ? raw : defaultValue;
    }

    return DesktopWindowState(
      hasNativeHeaderBar: readBool(
        'hasNativeHeaderBar',
        fallback.hasNativeHeaderBar,
      ),
      hasSystemDecorations: readBool(
        'hasSystemDecorations',
        fallback.hasSystemDecorations,
      ),
      isMinimized: readBool('isMinimized', fallback.isMinimized),
      isFocused: readBool('isFocused', fallback.isFocused),
      isMaximized: readBool('isMaximized', fallback.isMaximized),
      isHiddenToTray: readBool('isHiddenToTray', fallback.isHiddenToTray),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopWindowState &&
          runtimeType == other.runtimeType &&
          hasNativeHeaderBar == other.hasNativeHeaderBar &&
          hasSystemDecorations == other.hasSystemDecorations &&
          isMinimized == other.isMinimized &&
          isFocused == other.isFocused &&
          isMaximized == other.isMaximized &&
          isHiddenToTray == other.isHiddenToTray;

  @override
  int get hashCode => Object.hash(
    hasNativeHeaderBar,
    hasSystemDecorations,
    isMinimized,
    isFocused,
    isMaximized,
    isHiddenToTray,
  );
}
