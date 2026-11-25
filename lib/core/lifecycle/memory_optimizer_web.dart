import 'dart:async';

import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';

/// Web stub implementation of [MemoryOptimizer].
class MemoryOptimizer {
  static Timer? _periodicTimer;

  /// No-op on Web where the browser runtime manages memory directly.
  static void trim({MemoryTrimLevel level = MemoryTrimLevel.moderate}) {}

  /// Starts a periodic callback timer on Web matching native API signatures.
  static void startPeriodicTrimmer({
    Duration interval = const Duration(seconds: 10),
    void Function()? onTrim,
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      onTrim?.call();
    });
  }

  /// Stops the periodic timer if currently active.
  static void stopPeriodicTrimmer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
