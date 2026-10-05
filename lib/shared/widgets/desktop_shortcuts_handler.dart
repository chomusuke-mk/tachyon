import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';

/// Intercepts PC/Desktop shortcuts (ESC key, browser back key, Alt+Left,
/// mouse back button, and numeric seek 0-9) to navigate back, minimize active players,
/// or seek through the active track.
class DesktopShortcutsHandler extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget child;

  const DesktopShortcutsHandler({
    super.key,
    this.navigatorKey,
    required this.child,
  });

  @override
  State<DesktopShortcutsHandler> createState() =>
      _DesktopShortcutsHandlerState();
}

class _DesktopShortcutsHandlerState extends State<DesktopShortcutsHandler> {
  int _lastBackTriggerTime = 0;

  static final Map<LogicalKeyboardKey, int> _digitKeys = {
    LogicalKeyboardKey.digit0: 0,
    LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad9: 9,
  };

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      final isAltLeft =
          key == LogicalKeyboardKey.arrowLeft &&
          HardwareKeyboard.instance.isAltPressed;
      final isBackKey =
          key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.browserBack ||
          key == LogicalKeyboardKey.goBack ||
          isAltLeft;

      if (isBackKey) {
        return _triggerBack();
      }

      final hasModifiers = HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;

      // Spacebar: play/pause toggle (only without modifiers)
      if (key == LogicalKeyboardKey.space &&
          !hasModifiers &&
          !HardwareKeyboard.instance.isShiftPressed) {
        return _triggerPlayPause();
      }

      // Numeric seek 0-9
      if (!hasModifiers) {
        final digit = _digitKeys[key];
        if (digit != null) {
          final isTopRowDigit = key.keyId >= LogicalKeyboardKey.digit0.keyId &&
              key.keyId <= LogicalKeyboardKey.digit9.keyId;
          if (isTopRowDigit && HardwareKeyboard.instance.isShiftPressed) {
            return false;
          }
          return _triggerSeek(digit);
        }
      }
    }
    return false;
  }

  bool _triggerPlayPause() {
    if (_isTextInputFocused()) {
      return false;
    }

    try {
      final playback = context.read<PlaybackController?>();
      if (playback == null || playback.currentTrack == null) {
        return false;
      }

      playback.playOrPause();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kBackMouseButton) != 0) {
      _triggerBack();
    }
  }

  bool _isTextInputFocused() {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return false;
    final focusContext = primaryFocus.context;
    if (focusContext == null || !focusContext.mounted) return false;
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null ||
        focusContext.findAncestorWidgetOfExactType<TextField>() != null;
  }

  bool _triggerSeek(int digit) {
    if (_isTextInputFocused()) {
      return false;
    }

    try {
      final playback = context.read<PlaybackController?>();
      if (playback == null || playback.currentTrack == null) {
        return false;
      }

      final duration = playback.duration;
      if (duration <= Duration.zero) {
        return false;
      }

      final fraction = digit / 10.0;
      final targetMs = (duration.inMilliseconds * fraction)
          .round()
          .clamp(0, duration.inMilliseconds);
      playback.seek(Duration(milliseconds: targetMs));
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _triggerBack() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBackTriggerTime < 150) {
      return false;
    }

    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      _lastBackTriggerTime = now;
      navigator.maybePop();
      return true;
    }

    // Secondary fallback: if at root and FoldersScreen has navigated into a subfolder,
    // navigate up one folder level.
    try {
      final library = context.read<LibraryController?>();
      if (library != null && library.currentFolderPath != null) {
        _lastBackTriggerTime = now;
        library.navigateUpFolder();
        return true;
      }
    } catch (_) {}

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: widget.child,
    );
  }
}
