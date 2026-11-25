import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/memory_optimizer.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';

/// Coordinates application-wide memory, image cache, Skia cache, and native heap
/// trimming across [AppLifecycleMode] transitions.
class AppMemoryCoordinator {
  /// Default image cache entry count limit in foreground mode.
  static const int activeImageCacheMaxSize = kIsWeb ? 200 : 120;

  /// Default image cache byte budget in foreground mode.
  static const int activeImageCacheMaxBytes = (kIsWeb ? 32 : 16) * 1024 * 1024;

  /// Default Skia resource cache byte budget in foreground mode.
  static const int activeSkiaCacheMaxBytes = (kIsWeb ? 64 : 24) * 1024 * 1024;

  static final List<Timer> _pendingTrimTimers = <Timer>[];
  static AppLifecycleMode _lastAppliedMode = AppLifecycleMode.active;

  /// Cancels any delayed post-transition memory trim timers.
  static void cancelPendingTrims() {
    for (final timer in _pendingTrimTimers) {
      timer.cancel();
    }
    _pendingTrimTimers.clear();
  }

  /// Applies the cache and RAM reclamation policy for [mode].
  ///
  /// When [startTrimmerInActive] is false, the periodic trimmer is not started
  /// on return to [AppLifecycleMode.active] (useful for deterministic widget tests).
  static void applyPolicy(
    AppLifecycleMode mode, {
    bool startTrimmerInActive = true,
  }) {
    cancelPendingTrims();
    _lastAppliedMode = mode;

    switch (mode) {
      case AppLifecycleMode.active:
        PaintingBinding.instance.imageCache.maximumSize =
            activeImageCacheMaxSize;
        PaintingBinding.instance.imageCache.maximumSizeBytes =
            activeImageCacheMaxBytes;
        _setSkiaResourceCacheMaxBytes(activeSkiaCacheMaxBytes);
        MemoryOptimizer.trim(level: MemoryTrimLevel.light);
        if (startTrimmerInActive) {
          MemoryOptimizer.startPeriodicTrimmer();
        }
        break;

      case AppLifecycleMode.suspended:
        MemoryOptimizer.stopPeriodicTrimmer();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        _setSkiaResourceCacheMaxBytes(0);
        MemoryOptimizer.trim(level: MemoryTrimLevel.moderate);
        _scheduleDelayedTrim(
          const Duration(milliseconds: 350),
          expectedMode: AppLifecycleMode.suspended,
          level: MemoryTrimLevel.moderate,
        );
        break;

      case AppLifecycleMode.background:
        MemoryOptimizer.stopPeriodicTrimmer();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        PaintingBinding.instance.imageCache.maximumSize = 0;
        PaintingBinding.instance.imageCache.maximumSizeBytes = 0;
        ArtworkColorResolver.clearCache();
        _setSkiaResourceCacheMaxBytes(0);
        MemoryOptimizer.trim(level: MemoryTrimLevel.aggressive);
        _scheduleDelayedTrim(
          const Duration(milliseconds: 250),
          expectedMode: AppLifecycleMode.background,
          level: MemoryTrimLevel.aggressive,
        );
        _scheduleDelayedTrim(
          const Duration(milliseconds: 1000),
          expectedMode: AppLifecycleMode.background,
          level: MemoryTrimLevel.aggressive,
        );
        break;
    }
  }

  static void _scheduleDelayedTrim(
    Duration delay, {
    required AppLifecycleMode expectedMode,
    required MemoryTrimLevel level,
  }) {
    late final Timer timer;
    timer = Timer(delay, () {
      _pendingTrimTimers.remove(timer);
      if (_lastAppliedMode == expectedMode) {
        if (expectedMode == AppLifecycleMode.background) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          _setSkiaResourceCacheMaxBytes(0);
        }
        MemoryOptimizer.trim(level: level);
      }
    });
    _pendingTrimTimers.add(timer);
  }

  static void _setSkiaResourceCacheMaxBytes(int bytes) {
    try {
      SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes',
        bytes,
      );
    } catch (_) {}
  }
}
