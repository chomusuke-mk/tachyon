import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/app/app.dart';

/// Global overlay toast helper displaying floating error, success, and dismissible feedback messages.
abstract final class ToastUtils {
  /// Global navigator key owned by [App].
  static GlobalKey<NavigatorState> get navigatorKey => App.navigatorKey;

  static OverlayEntry? _currentOverlay;
  static _ToastWidgetState? _currentState;
  static Timer? _timer;

  static void _show(String message, Color bgColor, IconData icon) {
    // Immediately replace any currently visible toast when a new message arrives.
    _timer?.cancel();
    _killCurrent();

    final overlayState = navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    // Create the new animated overlay toast entry.
    _currentOverlay = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        bgColor: bgColor,
        icon: icon,
        onStateCreated: (state) => _currentState = state,
        onCloseTap: () => _hideCurrent(animate: true),
      ),
    );

    overlayState.insert(_currentOverlay!);

    // Schedule animated dismissal after 3 seconds.
    _timer = Timer(
      const Duration(seconds: 3),
      () => _hideCurrent(animate: true),
    );
  }

  static void _killCurrent() {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
      _currentState = null;
    }
  }

  static Future<void> _hideCurrent({bool animate = false}) async {
    final targetOverlay = _currentOverlay;
    if (targetOverlay == null) return;

    _timer?.cancel();

    if (animate && _currentState != null) {
      await _currentState!.reverse();
    }

    // Remove only if no newer toast replaced this overlay in the meantime.
    if (_currentOverlay == targetOverlay) {
      _killCurrent();
    }
  }

  /// Displays an error toast notification with [message].
  static void showError(String message) {
    _show(message, Colors.red.shade700, Icons.error_outline);
  }

  /// Displays a confirmation toast notification with [message].
  static void showSuccess(String message) {
    _show(message, Colors.green.shade700, Icons.check_circle_outline);
  }

  /// Immediately dismisses any visible overlay toast and cancels pending timers.
  static void dismissAll() {
    _timer?.cancel();
    _killCurrent();
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final Color bgColor;
  final IconData icon;
  final Function(_ToastWidgetState) onStateCreated;
  final VoidCallback onCloseTap;

  const _ToastWidget({
    required this.message,
    required this.bgColor,
    required this.icon,
    required this.onStateCreated,
    required this.onCloseTap,
  });

  @override
  _ToastWidgetState createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Slide-in animation from bottom with a subtle spring overshoot.
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeIn,
          ),
        );

    // Fade-in / fade-out opacity animation.
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  Future<void> reverse() async {
    if (mounted) {
      await _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            // Material supplies default overlay typography so text inherits theme styles.
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: widget.bgColor,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onCloseTap,
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
