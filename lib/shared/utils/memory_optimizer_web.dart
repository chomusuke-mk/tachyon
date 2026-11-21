import 'dart:async';

class MemoryOptimizer {
  static Timer? _periodicTimer;

  static void trim({bool aggressive = false}) {}

  static void startPeriodicTrimmer({
    Duration interval = const Duration(seconds: 10),
    void Function()? onTrim,
  }) {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) {
      onTrim?.call();
      trim();
    });
  }

  static void stopPeriodicTrimmer() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }
}
