import 'dart:async';

import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/logging/app_logger.dart';

/// Web stub implementation of [MemoryOptimizer].
class MemoryOptimizer {
  static const _log = ScopedLogger('MemoryOptimizer');
  static Timer? _periodicTimer;

  /// No-op on Web where the browser runtime manages memory directly.
  static void trim({MemoryTrimLevel level = MemoryTrimLevel.moderate}) {
    _log.vLazy(() => 'Web trim no-op (level=${level.name})');
  }

  /// Starts a periodic callback timer on Web matching native API signatures.
  static void startPeriodicTrimmer({
    Duration interval = const Duration(seconds: 10),
    void Function()? onTrim,
  }) {
    _periodicTimer?.cancel();
    _log.d('Starting periodic Web trimmer (interval=${interval.inSeconds}s)');
    _periodicTimer = Timer.periodic(interval, (_) {
      onTrim?.call();
    });
  }

  /// Stops the periodic timer if currently active.
  static void stopPeriodicTrimmer() {
    if (_periodicTimer != null) {
      _log.d('Stopping periodic Web trimmer');
    }
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
