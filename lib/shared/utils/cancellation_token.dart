import 'package:flutter/foundation.dart';

/// Lightweight token enabling cooperative cancellation of asynchronous operations.
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;

  /// Marks this token as cancelled and notifies all registered listeners.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }

  /// Registers a listener callback invoked immediately if already cancelled,
  /// or when [cancel] is called.
  void onCancel(VoidCallback callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }
}
