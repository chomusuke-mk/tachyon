import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/presentation/library_controller.dart';

/// Intercepts PC/Desktop navigation inputs (ESC key, browser back key, Alt+Left,
/// and mouse back button) to navigate back, minimize active players, or dismiss modal screens.
class DesktopBackNavigationHandler extends StatefulWidget {
  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget child;

  const DesktopBackNavigationHandler({
    super.key,
    this.navigatorKey,
    required this.child,
  });

  @override
  State<DesktopBackNavigationHandler> createState() =>
      _DesktopBackNavigationHandlerState();
}

class _DesktopBackNavigationHandlerState
    extends State<DesktopBackNavigationHandler> {
  int _lastTriggerTime = 0;

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
    }
    return false;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if ((event.buttons & kBackMouseButton) != 0) {
      _triggerBack();
    }
  }

  bool _triggerBack() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTriggerTime < 150) {
      return false;
    }

    final navigator =
        widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      _lastTriggerTime = now;
      navigator.maybePop();
      return true;
    }

    // Secondary fallback: if at root and FoldersScreen has navigated into a subfolder,
    // navigate up one folder level.
    try {
      final library = context.read<LibraryController?>();
      if (library != null && library.currentFolderPath != null) {
        _lastTriggerTime = now;
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
