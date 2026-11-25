import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_mode.dart';
import 'package:tachyon/core/lifecycle/memory_optimizer.dart';
import 'package:tachyon/core/logging/app_logger.dart';
import 'package:tachyon/shared/utils/artwork_color_resolver.dart';

/// Coordinates application-wide memory, image cache, Skia cache, and native heap
/// trimming across [AppLifecycleMode] transitions.
class AppMemoryCoordinator {
  static const _log = ScopedLogger('MemoryCoordinator');

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
    if (_pendingTrimTimers.isNotEmpty) {
      final count = _pendingTrimTimers.length;
      _log.vLazy(() => 'Cancelled $count pending delayed trim timer(s)');
    }
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
    final prevMode = _lastAppliedMode;
    _lastAppliedMode = mode;

    final imgCache = PaintingBinding.instance.imageCache;
    final entriesBefore = imgCache.currentSize;
    final bytesBefore = imgCache.currentSizeBytes;
    final liveBefore = imgCache.liveImageCount;

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
        _log.d(
          'applyPolicy(${prevMode.name}->${mode.name}): '
          'imageCache(entries=$entriesBefore, bytes=$bytesBefore, live=$liveBefore) '
          'restoredLimits=($activeImageCacheMaxSize, ${activeImageCacheMaxBytes}B) '
          'skia=${activeSkiaCacheMaxBytes}B trim=light startTrimmer=$startTrimmerInActive',
        );
        break;

      case AppLifecycleMode.suspended:
        MemoryOptimizer.stopPeriodicTrimmer();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        _setSkiaResourceCacheMaxBytes(0);
        MemoryOptimizer.trim(level: MemoryTrimLevel.moderate);
        _log.d(
          'applyPolicy(${prevMode.name}->${mode.name}): '
          'before imageCache(entries=$entriesBefore, bytes=$bytesBefore, live=$liveBefore) -> '
          'cleared imageCache + clearLiveImages(), skia=0B, trim=moderate, delayedTrim=350ms',
        );
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
        _log.d(
          'applyPolicy(${prevMode.name}->${mode.name}): '
          'before imageCache(entries=$entriesBefore, bytes=$bytesBefore, live=$liveBefore) -> '
          'cleared imageCache + maxSize=0 + ArtworkColorResolver.clearCache() + skia=0B, '
          'trim=aggressive, delayedTrims=250ms,1000ms',
        );
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
    _log.d(
      'Scheduled delayed trim: delay=${delay.inMilliseconds}ms expectedMode=${expectedMode.name} level=${level.name}',
    );
    timer = Timer(delay, () {
      _pendingTrimTimers.remove(timer);
      if (_lastAppliedMode == expectedMode) {
        if (expectedMode == AppLifecycleMode.background) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          _setSkiaResourceCacheMaxBytes(0);
        }
        _log.d(
          'Delayed trim executing: delay=${delay.inMilliseconds}ms mode=${expectedMode.name} level=${level.name}',
        );
        MemoryOptimizer.trim(level: level);
      } else {
        _log.d(
          'Delayed trim skipped: delay=${delay.inMilliseconds}ms expected=${expectedMode.name} current=${_lastAppliedMode.name}',
        );
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
    } catch (e) {
      _log.w('Skia.setResourceCacheMaxBytes($bytes) failed: $e');
    }
  }
}
